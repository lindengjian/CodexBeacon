import Foundation

public struct AppServerRequest: Equatable, Sendable {
  public let id: Int
  public let method: String
  public let threadID: String?

  fileprivate init(
    id: Int,
    method: AppServerRequestMethod,
    threadID: String? = nil
  ) {
    self.id = id
    self.method = method.rawValue
    self.threadID = threadID
  }
}

extension AppServerRequest {
  init(id: Int, method: String) {
    self.id = id
    self.method = method
    self.threadID = nil
  }
}

struct AppServerTaskMonitor {
  private static let snapshotRequestTimeout: TimeInterval = 6

  private let requestIDGenerator: AppServerRequestIDGenerator
  private var requests: [AppServerRequest] = []
  private var pendingRequests: [Int: PendingRequest] = [:]
  private var pendingSnapshotRequestTimes: [Int: Date] = [:]
  private var latestSnapshotProgressAt: Date?
  private var observedThreads: [String: ObservedThread] = [:]
  private var outstandingInitialReads: Set<String> = []
  private var snapshotThreadIDs: Set<String>?
  private var completedTaskIDs: Set<String> = []
  private var pendingThreadNames: [String: String] = [:]
  private var state = MonitoringState.notStarted
  init(requestIDGenerator: AppServerRequestIDGenerator) {
    self.requestIDGenerator = requestIDGenerator
  }

  var waitingTasks: [WaitingTask] {
    observedThreads.values.compactMap { thread in
      guard
        thread.isUserVisibleRoot,
        thread.taskState == .waitingForYou,
        let firstObservedAt = thread.waitingSince
      else {
        return nil
      }
      return WaitingTask(
        threadID: thread.id, firstObservedAt: firstObservedAt, title: thread.title)
    }
    .sorted {
      $0.firstObservedAt == $1.firstObservedAt
        ? $0.threadID < $1.threadID
        : $0.firstObservedAt < $1.firstObservedAt
    }
  }

  var allTaskTitles: [String: String] {
    var titles: [String: String] = [:]
    for thread in observedThreads.values {
      if thread.isUserVisibleRoot {
        if let title = thread.title ?? pendingThreadNames[thread.id] {
          titles[thread.id] = title
        }
      }
    }
    return titles
  }

  var allTaskSessionIds: [String: String] {
    var ids: [String: String] = [:]
    for thread in observedThreads.values {
      if thread.isUserVisibleRoot, let sessionId = thread.sessionId {
        ids[thread.id] = sessionId
      }
    }
    return ids
  }

  var unconfirmedCompletionTaskIDs: Set<String> {
    completedTaskIDs
  }

  var workingTaskIDs: [String] {
    let workingThreads = observedThreads.values.filter { thread in
      thread.isUserVisibleRoot && thread.taskState == .working
    }
    return workingThreads
      .map { (id: $0.id, observedAt: $0.observedAt) }
      .sorted {
        if $0.observedAt == $1.observedAt {
          return $0.id < $1.id
        }
        return $0.observedAt < $1.observedAt
      }
      .map { $0.id }
  }

  var status: BeaconStatus {
    currentStatus
  }

  mutating func confirmCompletions(_ ids: Set<String>) {
    completedTaskIDs.subtract(ids)
  }

  mutating func connectionEstablished(
    protocolCompatible: Bool,
    observedAt: Date
  ) -> BeaconStatus {
    guard protocolCompatible else {
      return fail()
    }

    state = .collectingEvidence
    requests.removeAll()
    pendingRequests.removeAll()
    pendingSnapshotRequestTimes.removeAll()
    latestSnapshotProgressAt = nil
    observedThreads.removeAll()
    outstandingInitialReads.removeAll()
    snapshotThreadIDs = nil
    requestLoadedThreads(observedAt: observedAt)
    return .monitoringUnavailable
  }

  mutating func connectionFailed() -> BeaconStatus {
    fail()
  }

  mutating func observationBecameStale() -> BeaconStatus {
    fail()
  }

  mutating func snapshotRequested(observedAt: Date) -> BeaconStatus {
    guard
      state == .available || state == .collectingEvidence
    else {
      return currentStatus
    }
    if hasPendingLoadedThreadsRead || hasPendingThreadRead {
      guard hasTimedOutSnapshotRequest(at: observedAt) else {
        return currentStatus
      }
      discardTimedOutSnapshotRequests()
    }
    requestLoadedThreads(observedAt: observedAt)
    return currentStatus
  }

  mutating func handle(message: String, observedAt: Date) -> BeaconStatus {
    guard state != .notStarted, state != .unavailable else {
      return .monitoringUnavailable
    }
    guard let data = message.data(using: .utf8) else {
      return fail()
    }

    do {
      // Capture threadName from any message (notification, response, or
      // unclassified) so it is available when the thread is first read.
      capturePendingThreadName(from: data)

      let header = try JSONDecoder().decode(MessageHeader.self, from: data)
      if let method = header.method {
        guard
          AppServerNotificationMethod(rawValue: method) == .threadStatusChanged
        else {
          return currentStatus
        }
        return try handleStatusNotification(data, observedAt: observedAt)
      }

      guard let requestID = header.id else {
        return currentStatus
      }
      guard let pendingRequest = pendingRequests.removeValue(forKey: requestID) else {
        return currentStatus
      }
      if pendingSnapshotRequestTimes.removeValue(forKey: requestID) != nil {
        latestSnapshotProgressAt = observedAt
      }

      if header.error != nil {
        switch pendingRequest {
        case .loadedThreads:
          return currentStatus
        case .thread(let threadID):
          return handleThreadReadFailure(threadID)
        case .latestTurn:
          return currentStatus
        }
      }

      switch pendingRequest {
      case .loadedThreads:
        return try handleLoadedThreadsResponse(data, observedAt: observedAt)
      case .thread(let threadID):
        return try handleThreadResponse(
          data,
          expectedThreadID: threadID,
          observedAt: observedAt
        )
      case .latestTurn(let threadID):
        return try handleLatestTurnResponse(
          data,
          expectedThreadID: threadID,
          observedAt: observedAt
        )
      }
    } catch {
      return fail()
    }
  }

  mutating func drainRequests() -> [AppServerRequest] {
    defer { requests.removeAll() }
    return requests
  }

  private mutating func requestLoadedThreads(observedAt: Date) {
    if pendingSnapshotRequestTimes.isEmpty {
      latestSnapshotProgressAt = observedAt
    }
    let request = AppServerRequest(
      id: requestIDGenerator.next(),
      method: .loadedThreads
    )
    pendingRequests[request.id] = .loadedThreads
    pendingSnapshotRequestTimes[request.id] = observedAt
    requests.append(request)
  }

  private mutating func requestThread(_ threadID: String, observedAt: Date) {
    if pendingSnapshotRequestTimes.isEmpty {
      latestSnapshotProgressAt = observedAt
    }
    let request = AppServerRequest(
      id: requestIDGenerator.next(),
      method: .readThread,
      threadID: threadID
    )
    pendingRequests[request.id] = .thread(threadID)
    pendingSnapshotRequestTimes[request.id] = observedAt
    requests.append(request)
  }

  private mutating func requestLatestTurn(_ threadID: String) {
    let request = AppServerRequest(
      id: requestIDGenerator.next(),
      method: .listTurns,
      threadID: threadID
    )
    pendingRequests[request.id] = .latestTurn(threadID)
    requests.append(request)
  }

  private mutating func handleLoadedThreadsResponse(
    _ data: Data,
    observedAt: Date
  ) throws -> BeaconStatus {
    let response = try JSONDecoder().decode(
      LoadedThreadsResponse.self,
      from: data
    )
    let threadIDs = response.result.data

    outstandingInitialReads = Set(threadIDs)
    snapshotThreadIDs = Set(threadIDs)
    guard !threadIDs.isEmpty else {
      state = .available
      reconcileSnapshot()
      return aggregateStatus
    }

    for threadID in threadIDs {
      requestThread(threadID, observedAt: observedAt)
    }
    return currentStatus
  }

  private mutating func handleThreadResponse(
    _ data: Data,
    expectedThreadID: String,
    observedAt: Date
  ) throws -> BeaconStatus {
    let response = try JSONDecoder().decode(ThreadReadResponse.self, from: data)
    let thread = response.result.thread
    guard thread.id == expectedThreadID else {
      return fail()
    }
    let isUserVisibleRoot =
      thread.source?.isDesktop == true
      && thread.threadSource != "system"
      && thread.parentThreadId == nil
      && (!thread.ephemeral || thread.threadSource == "user")
    let taskState: ObservedTaskState
    if isUserVisibleRoot {
      guard
        let status = thread.status,
        let state = self.taskState(from: status)
      else {
        if observedThreads[thread.id]?.isUserVisibleRoot == true {
          return currentStatus
        }
        return fail()
      }
      taskState = state
    } else {
      taskState = .idle
    }
    observedThreads[thread.id] = updatedThread(
      id: thread.id,
      sessionId: thread.sessionId,
      isUserVisibleRoot: isUserVisibleRoot,
      taskState: taskState,
      previous: observedThreads[thread.id],
      observedAt: observedAt,
      title: thread.title
        ?? thread.threadName
        ?? thread.name
        ?? pendingThreadNames[thread.id]
    )
    outstandingInitialReads.remove(thread.id)

    guard outstandingInitialReads.isEmpty, !hasPendingThreadRead else {
      return currentStatus
    }
    state = .available
    reconcileSnapshot()
    return aggregateStatus
  }

  private mutating func handleThreadReadFailure(_ threadID: String) -> BeaconStatus {
    outstandingInitialReads.remove(threadID)

    guard outstandingInitialReads.isEmpty, !hasPendingThreadRead else {
      return currentStatus
    }
    guard state == .available else {
      return .monitoringUnavailable
    }
    reconcileSnapshot()
    return aggregateStatus
  }

  private mutating func handleLatestTurnResponse(
    _ data: Data,
    expectedThreadID: String,
    observedAt: Date
  ) throws -> BeaconStatus {
    let response = try JSONDecoder().decode(TurnsListResponse.self, from: data)
    guard let thread = observedThreads[expectedThreadID] else {
      return fail()
    }

    let taskState: ObservedTaskState
    if let latestTurn = response.result.data.first {
      guard let turnStatus = TurnStatus(rawValue: latestTurn.status) else {
        return fail()
      }
      switch turnStatus {
      case .completed:
        if thread.isUserVisibleRoot {
          completedTaskIDs.insert(expectedThreadID)
        }
        taskState = .idle
      case .failed, .interrupted, .cancelled, .canceled:
        taskState = .idle
      case .inProgress:
        taskState = .working
      }
    } else {
      taskState = .idle
    }

    observedThreads[expectedThreadID] = updatedThread(
      id: expectedThreadID,
      isUserVisibleRoot: thread.isUserVisibleRoot,
      taskState: taskState,
      previous: thread,
      observedAt: observedAt
    )
    return currentStatus
  }

  private mutating func handleStatusNotification(
    _ data: Data,
    observedAt: Date
  ) throws -> BeaconStatus {
    let notification = try JSONDecoder().decode(
      ThreadStatusChangedNotification.self,
      from: data
    )
    let threadID = notification.params.threadID
    let previousThread = observedThreads[threadID]
    guard let taskState = taskState(from: notification.params.status) else {
      guard previousThread?.isUserVisibleRoot == true else {
        return currentStatus
      }
      if !hasPendingRead(for: threadID) {
          requestThread(threadID, observedAt: observedAt)
      }
      return currentStatus
    }

    guard let previousThread else {
      state = .collectingEvidence
      if let threadName = notification.params.threadName {
        pendingThreadNames[threadID] = threadName
      }
      if !hasPendingRead(for: threadID) {
        requestThread(threadID, observedAt: observedAt)
      }
      return .monitoringUnavailable
    }

    let resolvedTitle = notification.params.threadName
      ?? pendingThreadNames[threadID]
      ?? previousThread.title
    observedThreads[threadID] = updatedThread(
      id: threadID,
      isUserVisibleRoot: previousThread.isUserVisibleRoot,
      taskState: taskState,
      previous: previousThread,
      observedAt: observedAt,
      title: resolvedTitle
    )
    if taskState == .idle, previousThread.taskState.isActive,
      !hasPendingLatestTurnRead(for: threadID)
    {
      requestLatestTurn(threadID)
    }
    return state == .available ? aggregateStatus : .monitoringUnavailable
  }

  private func taskState(from status: ProtocolThreadStatus) -> ObservedTaskState? {
    guard let statusType = ProtocolThreadStatusType(rawValue: status.type) else {
      return nil
    }

    switch statusType {
    case .idle:
      return .idle
    case .active:
      guard let flags = status.activeFlags else {
        return nil
      }
      let activeFlags = flags.compactMap(AppServerActiveFlag.init(rawValue:))
      guard activeFlags.count == flags.count else {
        return nil
      }
      return activeFlags.contains(.waitingOnApproval)
        || activeFlags.contains(.waitingOnUserInput)
        ? .waitingForYou
        : .working
    case .notLoaded, .systemError:
      return nil
    }
  }

  private var aggregateStatus: BeaconStatus {
    let userVisibleStates = observedThreads.values.compactMap { thread in
      thread.isUserVisibleRoot ? thread.taskState : nil
    }
    if userVisibleStates.contains(.waitingForYou) {
      return .waitingForYou
    }
    if userVisibleStates.contains(.working) {
      return .working
    }
    if !completedTaskIDs.isEmpty {
      return .completed
    }
    return .idle
  }

  private var currentStatus: BeaconStatus {
    state == .available ? aggregateStatus : .monitoringUnavailable
  }

  private var hasPendingThreadRead: Bool {
    pendingRequests.values.contains {
      guard case .thread = $0 else {
        return false
      }
      return true
    }
  }

  /// Extracts threadName from any message and caches it for later use.
  /// Handles three paths in priority order:
  /// 1. Notification params:   params.threadName (or params.thread_name)
  /// 2. Nested thread object:  params.thread.threadName
  /// 3. Response result:       result.thread.threadName
  ///
  /// Path 3 is essential for re-activated sessions whose status-change
  /// notification may omit threadName; the thread/read response still has it.
  private mutating func capturePendingThreadName(from data: Data) {
    guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return
    }

    // Path 1 — notification params (e.g. thread/status/changed, thread/updated)
    if let params = raw["params"] as? [String: Any],
      let threadID = (params["threadId"] as? String) ?? (params["thread_id"] as? String)
    {
      if let threadName = params["threadName"] as? String
        ?? params["thread_name"] as? String
      {
        pendingThreadNames[threadID] = threadName
        return
      }
      // Path 2 — nested thread object: params.thread.threadName
      if let thread = params["thread"] as? [String: Any],
        let threadName = thread["threadName"] as? String
          ?? thread["thread_name"] as? String
      {
        pendingThreadNames[threadID] = threadName
        return
      }
    }

    // Path 3 — response result (e.g. thread/read)
    if let result = raw["result"] as? [String: Any],
      let thread = result["thread"] as? [String: Any],
      let threadID = thread["id"] as? String,
      let threadName = thread["threadName"] as? String
        ?? thread["thread_name"] as? String
        ?? thread["name"] as? String
    {
      pendingThreadNames[threadID] = threadName
    }
  }

  private var hasPendingLoadedThreadsRead: Bool {
    pendingRequests.values.contains { pendingRequest in
      if case .loadedThreads = pendingRequest {
        return true
      }
      return false
    }
  }

  private func hasPendingRead(for threadID: String) -> Bool {
    pendingRequests.values.contains {
      guard case .thread(let pendingThreadID) = $0 else {
        return false
      }
      return pendingThreadID == threadID
    }
  }

  private func hasPendingLatestTurnRead(for threadID: String) -> Bool {
    pendingRequests.values.contains {
      guard case .latestTurn(let pendingThreadID) = $0 else {
        return false
      }
      return pendingThreadID == threadID
    }
  }

  private mutating func fail() -> BeaconStatus {
    state = .unavailable
    requests.removeAll()
    pendingRequests.removeAll()
    pendingSnapshotRequestTimes.removeAll()
    latestSnapshotProgressAt = nil
    outstandingInitialReads.removeAll()
    snapshotThreadIDs = nil
    return .monitoringUnavailable
  }

  private mutating func reconcileSnapshot() {
    guard let snapshotThreadIDs else {
      return
    }
    observedThreads = observedThreads.filter { snapshotThreadIDs.contains($0.key) }
    self.snapshotThreadIDs = nil
  }

  private func hasTimedOutSnapshotRequest(at observedAt: Date) -> Bool {
    guard !pendingSnapshotRequestTimes.isEmpty else { return false }
    let lastProgressAt = latestSnapshotProgressAt
      ?? pendingSnapshotRequestTimes.values.max()
      ?? observedAt
    return observedAt.timeIntervalSince(lastProgressAt) >= Self.snapshotRequestTimeout
  }

  private mutating func discardTimedOutSnapshotRequests() {
    for requestID in pendingSnapshotRequestTimes.keys {
      pendingRequests.removeValue(forKey: requestID)
    }
    pendingSnapshotRequestTimes.removeAll()
    latestSnapshotProgressAt = nil
    outstandingInitialReads.removeAll()
    snapshotThreadIDs = nil
  }

  private func updatedThread(
    id: String,
    sessionId: String? = nil,
    isUserVisibleRoot: Bool,
    taskState: ObservedTaskState,
    previous: ObservedThread?,
    observedAt: Date,
    title: String? = nil
  ) -> ObservedThread {
    ObservedThread(
      id: id,
      sessionId: sessionId ?? previous?.sessionId,
      isUserVisibleRoot: isUserVisibleRoot,
      taskState: taskState,
      waitingSince: taskState == .waitingForYou
        ? previous?.waitingSince ?? observedAt
        : nil,
      observedAt: previous?.observedAt ?? observedAt,
      title: title ?? previous?.title
    )
  }
}

private enum PendingRequest {
  case loadedThreads
  case thread(String)
  case latestTurn(String)
}

private enum AppServerRequestMethod: String {
  case loadedThreads = "thread/loaded/list"
  case readThread = "thread/read"
  case listTurns = "thread/turns/list"
}

private enum AppServerNotificationMethod: String {
  case threadStatusChanged = "thread/status/changed"
}

private enum ProtocolThreadStatusType: String {
  case notLoaded
  case idle
  case systemError
  case active
}

private enum AppServerActiveFlag: String {
  case waitingOnApproval
  case waitingOnUserInput
}

private struct ObservedThread {
  let id: String
  let sessionId: String?
  let isUserVisibleRoot: Bool
  let taskState: ObservedTaskState
  let waitingSince: Date?
  let observedAt: Date
  let title: String?
}

private enum ObservedTaskState: Equatable {
  case idle
  case working
  case waitingForYou

  var isActive: Bool {
    self == .working || self == .waitingForYou
  }
}

private enum MonitoringState {
  case notStarted
  case collectingEvidence
  case available
  case unavailable
}

private struct MessageHeader: Decodable {
  let id: Int?
  let method: String?
  let error: AppServerResponseError?
}

private struct AppServerResponseError: Decodable {}

private struct LoadedThreadsResponse: Decodable {
  let result: LoadedThreadsResult
}

private struct LoadedThreadsResult: Decodable {
  let data: [String]
}

private struct ThreadReadResponse: Decodable {
  let result: ThreadReadResult
}

private struct ThreadReadResult: Decodable {
  let thread: ProtocolThread
}

private struct ProtocolThread: Decodable {
  let id: String
  let sessionId: String?
  let source: ProtocolThreadSource?
  let threadSource: String?
  let ephemeral: Bool
  let parentThreadId: String?
  let status: ProtocolThreadStatus?
  let title: String?
  let threadName: String?
  let name: String?
}

private enum ProtocolThreadSource: Decodable {
  case named(String)
  case nonDesktop

  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let source = try? container.decode(String.self) {
      self = .named(source)
    } else {
      self = .nonDesktop
    }
  }

  var isDesktop: Bool {
    guard case .named("vscode") = self else {
      return false
    }
    return true
  }
}

private struct ProtocolThreadStatus: Decodable {
  let type: String
  let activeFlags: [String]?
}

private struct ThreadStatusChangedNotification: Decodable {
  let params: ThreadStatusChangedParameters
}

private struct ThreadStatusChangedParameters: Decodable {
  let threadID: String
  let status: ProtocolThreadStatus
  let threadName: String?

  private enum CodingKeys: String, CodingKey {
    case threadID = "threadId"
    case status
    case threadName
  }
}

private struct TurnsListResponse: Decodable {
  let result: TurnsListResult
}

private struct TurnsListResult: Decodable {
  let data: [ProtocolTurn]
}

private struct ProtocolTurn: Decodable {
  let status: String
}

private enum TurnStatus: String {
  case inProgress
  case completed
  case interrupted
  case failed
  case cancelled
  case canceled
}
