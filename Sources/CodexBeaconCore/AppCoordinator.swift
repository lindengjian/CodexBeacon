import Foundation

public enum BeaconEffect: Equatable, Sendable {
  case showBeacon
  case hideBeacon
}

public struct AppServerRequest: Equatable, Sendable {
  public let id: Int
  public let method: String
  public let threadID: String?

  public init(id: Int, method: String, threadID: String? = nil) {
    self.id = id
    self.method = method
    self.threadID = threadID
  }
}

@MainActor
public final class AppCoordinator {
  public private(set) var viewState = BeaconViewState.idle

  private var effects: [BeaconEffect] = []
  private var appServerRequests: [AppServerRequest] = []
  private var pendingRequests: [Int: PendingRequest] = [:]
  private var observedThreads: [String: ObservedThread] = [:]
  private var outstandingInitialReads: Set<String> = []
  private var monitoringState = MonitoringState.notStarted
  private var nextRequestID = 1
  private var hasStarted = false

  public init() {}

  public func start() {
    guard !hasStarted else {
      return
    }

    hasStarted = true
    effects.append(.showBeacon)
  }

  public func handle(_ event: ApplicationEvent) {
    switch event {
    case .task(.noActiveTasksObserved):
      viewState.present(.idle)
    case .task(.monitoringConnectionEstablished(let protocolCompatible)):
      guard protocolCompatible else {
        failMonitoring()
        return
      }
      monitoringState = .collectingEvidence
      appServerRequests.removeAll()
      pendingRequests.removeAll()
      observedThreads.removeAll()
      outstandingInitialReads.removeAll()
      viewState.present(.monitoringUnavailable)
      requestLoadedThreads()
    case .task(.monitoringConnectionFailed),
      .task(.monitoringObservationBecameStale):
      failMonitoring()
    case .task(.appServerMessage(let message)):
      handleAppServerMessage(message)
    case .time(.advanced(let date)):
      viewState.lastUpdatedAt = date
    case .system(.reduceMotionChanged(let reducesMotion)):
      viewState.reducesMotion = reducesMotion
    case .system(.visibilityChanged(let isVisible)):
      guard viewState.isVisible != isVisible else {
        return
      }

      viewState.isVisible = isVisible
      effects.append(isVisible ? .showBeacon : .hideBeacon)
    }
  }

  public func drainEffects() -> [BeaconEffect] {
    defer { effects.removeAll() }
    return effects
  }

  public func drainAppServerRequests() -> [AppServerRequest] {
    defer { appServerRequests.removeAll() }
    return appServerRequests
  }

  private func requestLoadedThreads() {
    let request = AppServerRequest(
      id: nextRequestID,
      method: "thread/loaded/list"
    )
    nextRequestID += 1
    pendingRequests[request.id] = .loadedThreads
    appServerRequests.append(request)
  }

  private func requestThread(_ threadID: String) {
    let request = AppServerRequest(
      id: nextRequestID,
      method: "thread/read",
      threadID: threadID
    )
    nextRequestID += 1
    pendingRequests[request.id] = .thread(threadID)
    appServerRequests.append(request)
  }

  private func handleAppServerMessage(_ message: String) {
    guard monitoringState != .notStarted, monitoringState != .unavailable else {
      viewState.present(.monitoringUnavailable)
      return
    }

    guard
      let data = message.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data),
      let envelope = object as? [String: Any]
    else {
      failMonitoring()
      return
    }

    if envelope["method"] as? String == "thread/status/changed" {
      handleThreadStatusChanged(envelope)
      return
    }

    guard
      let requestID = envelope["id"] as? Int,
      let pendingRequest = pendingRequests.removeValue(forKey: requestID),
      envelope["error"] == nil
    else {
      failMonitoring()
      return
    }

    switch pendingRequest {
    case .loadedThreads:
      handleLoadedThreadsResponse(envelope)
    case .thread(let threadID):
      handleThreadResponse(envelope, expectedThreadID: threadID)
    }
  }

  private func handleLoadedThreadsResponse(_ envelope: [String: Any]) {
    guard
      let result = envelope["result"] as? [String: Any],
      let threadIDs = result["data"] as? [String]
    else {
      failMonitoring()
      return
    }

    observedThreads.removeAll()
    outstandingInitialReads = Set(threadIDs)
    guard !threadIDs.isEmpty else {
      monitoringState = .available
      viewState.present(.idle)
      return
    }

    for threadID in threadIDs {
      requestThread(threadID)
    }
  }

  private func handleThreadResponse(
    _ envelope: [String: Any],
    expectedThreadID: String
  ) {
    guard
      let result = envelope["result"] as? [String: Any],
      let thread = result["thread"] as? [String: Any],
      let threadID = thread["id"] as? String,
      threadID == expectedThreadID,
      let isEphemeral = thread["ephemeral"] as? Bool,
      let status = thread["status"] as? [String: Any],
      let isWorking = workingState(from: status)
    else {
      failMonitoring()
      return
    }

    let isUserVisibleRoot =
      !isEphemeral
      && thread["threadSource"] as? String != "system"
      && thread["parentThreadId"] as? String == nil
    observedThreads[threadID] = ObservedThread(
      isUserVisibleRoot: isUserVisibleRoot,
      isWorking: isWorking
    )
    outstandingInitialReads.remove(threadID)

    guard outstandingInitialReads.isEmpty else {
      return
    }
    let hasPendingThreadRead = pendingRequests.values.contains {
      guard case .thread = $0 else {
        return false
      }
      return true
    }
    guard !hasPendingThreadRead else {
      return
    }
    monitoringState = .available
    presentAggregate()
  }

  private func handleThreadStatusChanged(_ envelope: [String: Any]) {
    guard
      let params = envelope["params"] as? [String: Any],
      let threadID = params["threadId"] as? String,
      let status = params["status"] as? [String: Any],
      let isWorking = workingState(from: status)
    else {
      failMonitoring()
      return
    }

    guard let previousThread = observedThreads[threadID] else {
      monitoringState = .collectingEvidence
      viewState.present(.monitoringUnavailable)
      let alreadyRequested = pendingRequests.values.contains {
        guard case .thread(let pendingThreadID) = $0 else {
          return false
        }
        return pendingThreadID == threadID
      }
      if !alreadyRequested {
        requestThread(threadID)
      }
      return
    }

    observedThreads[threadID] = ObservedThread(
      isUserVisibleRoot: previousThread.isUserVisibleRoot,
      isWorking: isWorking
    )
    presentAggregate()
  }

  private func workingState(from status: [String: Any]) -> Bool? {
    guard let statusType = status["type"] as? String else {
      return nil
    }

    switch statusType {
    case "idle":
      return false
    case "notLoaded":
      return nil
    case "active":
      guard let flags = status["activeFlags"] as? [String] else {
        return nil
      }
      return !flags.contains("waitingOnApproval")
        && !flags.contains("waitingOnUserInput")
    case "systemError":
      return nil
    default:
      return nil
    }
  }

  private func presentAggregate() {
    guard monitoringState == .available else {
      viewState.present(.monitoringUnavailable)
      return
    }
    viewState.present(
      observedThreads.values.contains {
        $0.isUserVisibleRoot && $0.isWorking
      } ? .working : .idle
    )
  }

  private func failMonitoring() {
    monitoringState = .unavailable
    appServerRequests.removeAll()
    pendingRequests.removeAll()
    outstandingInitialReads.removeAll()
    viewState.present(.monitoringUnavailable)
  }
}

private enum PendingRequest {
  case loadedThreads
  case thread(String)
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
