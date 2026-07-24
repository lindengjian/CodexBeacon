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

struct AppServerTaskMonitor {
  private var requests: [AppServerRequest] = []
  private var pendingRequests: [Int: PendingRequest] = [:]
  private var observedThreads: [String: ObservedThread] = [:]
  private var outstandingInitialReads: Set<String> = []
  private var state = MonitoringState.notStarted
  private var nextRequestID = 1

  mutating func connectionEstablished(
    protocolCompatible: Bool
  ) -> BeaconStatus {
    guard protocolCompatible else {
      return fail()
    }

    state = .collectingEvidence
    requests.removeAll()
    pendingRequests.removeAll()
    observedThreads.removeAll()
    outstandingInitialReads.removeAll()
    requestLoadedThreads()
    return .monitoringUnavailable
  }

  mutating func connectionFailed() -> BeaconStatus {
    fail()
  }

  mutating func observationBecameStale() -> BeaconStatus {
    fail()
  }

  mutating func handle(message: String) -> BeaconStatus {
    guard state != .notStarted, state != .unavailable else {
      return .monitoringUnavailable
    }
    guard let data = message.data(using: .utf8) else {
      return fail()
    }

    do {
      let header = try JSONDecoder().decode(MessageHeader.self, from: data)
      if let method = header.method {
        guard
          AppServerNotificationMethod(rawValue: method) == .threadStatusChanged
        else {
          return currentStatus
        }
        return try handleStatusNotification(data)
      }

      guard
        let requestID = header.id,
        let pendingRequest = pendingRequests.removeValue(forKey: requestID)
      else {
        return fail()
      }

      switch pendingRequest {
      case .loadedThreads:
        return try handleLoadedThreadsResponse(data)
      case .thread(let threadID):
        return try handleThreadResponse(data, expectedThreadID: threadID)
      }
    } catch {
      return fail()
    }
  }

  mutating func drainRequests() -> [AppServerRequest] {
    defer { requests.removeAll() }
    return requests
  }

  private mutating func requestLoadedThreads() {
    let request = AppServerRequest(
      id: nextRequestID,
      method: .loadedThreads
    )
    nextRequestID += 1
    pendingRequests[request.id] = .loadedThreads
    requests.append(request)
  }

  private mutating func requestThread(_ threadID: String) {
    let request = AppServerRequest(
      id: nextRequestID,
      method: .readThread,
      threadID: threadID
    )
    nextRequestID += 1
    pendingRequests[request.id] = .thread(threadID)
    requests.append(request)
  }

  private mutating func handleLoadedThreadsResponse(
    _ data: Data
  ) throws -> BeaconStatus {
    let response = try JSONDecoder().decode(
      LoadedThreadsResponse.self,
      from: data
    )
    let threadIDs = response.result.data

    observedThreads.removeAll()
    outstandingInitialReads = Set(threadIDs)
    guard !threadIDs.isEmpty else {
      state = .available
      return .idle
    }

    for threadID in threadIDs {
      requestThread(threadID)
    }
    return .monitoringUnavailable
  }

  private mutating func handleThreadResponse(
    _ data: Data,
    expectedThreadID: String
  ) throws -> BeaconStatus {
    let response = try JSONDecoder().decode(ThreadReadResponse.self, from: data)
    let thread = response.result.thread
    guard thread.id == expectedThreadID else {
      return fail()
    }
    let isUserVisibleRoot =
      !thread.ephemeral
      && thread.threadSource != "system"
      && thread.parentThreadId == nil
    let isWorking: Bool
    if isUserVisibleRoot {
      guard
        let status = thread.status,
        let workingState = workingState(from: status)
      else {
        return fail()
      }
      isWorking = workingState
    } else {
      isWorking = false
    }
    observedThreads[thread.id] = ObservedThread(
      isUserVisibleRoot: isUserVisibleRoot,
      isWorking: isWorking
    )
    outstandingInitialReads.remove(thread.id)

    guard outstandingInitialReads.isEmpty, !hasPendingThreadRead else {
      return .monitoringUnavailable
    }
    state = .available
    return aggregateStatus
  }

  private mutating func handleStatusNotification(
    _ data: Data
  ) throws -> BeaconStatus {
    let notification = try JSONDecoder().decode(
      ThreadStatusChangedNotification.self,
      from: data
    )
    let threadID = notification.params.threadID
    guard let isWorking = workingState(from: notification.params.status) else {
      return fail()
    }

    guard let previousThread = observedThreads[threadID] else {
      state = .collectingEvidence
      if !hasPendingRead(for: threadID) {
        requestThread(threadID)
      }
      return .monitoringUnavailable
    }

    observedThreads[threadID] = ObservedThread(
      isUserVisibleRoot: previousThread.isUserVisibleRoot,
      isWorking: isWorking
    )
    return state == .available ? aggregateStatus : .monitoringUnavailable
  }

  private func workingState(from status: ProtocolThreadStatus) -> Bool? {
    guard let statusType = ProtocolThreadStatusType(rawValue: status.type) else {
      return nil
    }

    switch statusType {
    case .idle:
      return false
    case .active:
      guard let flags = status.activeFlags else {
        return nil
      }
      let activeFlags = flags.compactMap(AppServerActiveFlag.init(rawValue:))
      guard activeFlags.count == flags.count else {
        return nil
      }
      return !activeFlags.contains(.waitingOnApproval)
        && !activeFlags.contains(.waitingOnUserInput)
    case .notLoaded, .systemError:
      return nil
    }
  }

  private var aggregateStatus: BeaconStatus {
    observedThreads.values.contains {
      $0.isUserVisibleRoot && $0.isWorking
    } ? .working : .idle
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

  private func hasPendingRead(for threadID: String) -> Bool {
    pendingRequests.values.contains {
      guard case .thread(let pendingThreadID) = $0 else {
        return false
      }
      return pendingThreadID == threadID
    }
  }

  private mutating func fail() -> BeaconStatus {
    state = .unavailable
    requests.removeAll()
    pendingRequests.removeAll()
    outstandingInitialReads.removeAll()
    return .monitoringUnavailable
  }
}

private enum PendingRequest {
  case loadedThreads
  case thread(String)
}

private enum AppServerRequestMethod: String {
  case loadedThreads = "thread/loaded/list"
  case readThread = "thread/read"
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
  let isUserVisibleRoot: Bool
  let isWorking: Bool
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
}

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
  let threadSource: String?
  let ephemeral: Bool
  let parentThreadId: String?
  let status: ProtocolThreadStatus?
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

  private enum CodingKeys: String, CodingKey {
    case threadID = "threadId"
    case status
  }
}
