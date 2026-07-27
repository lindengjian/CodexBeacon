import Foundation

public enum BeaconEffect: Equatable, Sendable {
  case showBeacon
  case hideBeacon
  case activateCodex(threadID: String?)
}

@MainActor
public final class AppCoordinator {
  public private(set) var viewState = BeaconViewState.idle

  private var effects: [BeaconEffect] = []
  private var taskMonitor = AppServerTaskMonitor()
  private let requiresSharedRuntimeEvidence: Bool
  private var sharedRuntimeValidated: Bool
  private var hasStarted = false
  private var observationTime = Date()

  public init(requiresSharedRuntimeEvidence: Bool = false) {
    self.requiresSharedRuntimeEvidence = requiresSharedRuntimeEvidence
    sharedRuntimeValidated = !requiresSharedRuntimeEvidence
  }

  public func start() {
    guard !hasStarted else {
      return
    }

    hasStarted = true
    viewState.present(.monitoringUnavailable)
    effects.append(.showBeacon)
  }

  public func handle(_ event: ApplicationEvent) {
    switch event {
    case .task(.monitoringConnectionEstablished(let protocolCompatible)):
      sharedRuntimeValidated = !requiresSharedRuntimeEvidence
      presentTaskStatus(
        taskMonitor.connectionEstablished(protocolCompatible: protocolCompatible)
      )
    case .task(.monitoringRuntimeValidated):
      sharedRuntimeValidated = true
      presentTaskStatus(taskMonitor.status)
    case .task(.monitoringConnectionFailed):
      sharedRuntimeValidated = false
      presentTaskStatus(taskMonitor.connectionFailed())
    case .task(.monitoringObservationBecameStale):
      presentTaskStatus(taskMonitor.observationBecameStale())
    case .task(.appServerMessage(let message)):
      let status = taskMonitor.handle(message: message, observedAt: observationTime)
      presentTaskStatus(sharedRuntimeValidated ? status : .monitoringUnavailable)
    case .time(.advanced(let date)):
      observationTime = date
      viewState.lastUpdatedAt = date
    case .system(.reduceMotionChanged(let reducesMotion)):
      viewState.reducesMotion = reducesMotion
    case .system(.visibilityChanged(let isVisible)):
      guard viewState.isVisible != isVisible else {
        return
      }

      viewState.isVisible = isVisible
      effects.append(isVisible ? .showBeacon : .hideBeacon)
    case .user(.beaconActivated):
      let waitingThreadID = taskMonitor.waitingTasks.first?.threadID
      taskMonitor.confirmCompletions()
      presentTaskStatus(taskMonitor.status)
      effects.append(.activateCodex(threadID: waitingThreadID))
    }
  }

  public func drainEffects() -> [BeaconEffect] {
    defer { effects.removeAll() }
    return effects
  }

  public func drainAppServerRequests() -> [AppServerRequest] {
    taskMonitor.drainRequests()
  }

  private func presentTaskStatus(_ status: BeaconStatus) {
    viewState.present(
      status,
      waitingTasks: taskMonitor.waitingTasks,
      unconfirmedCompletionTaskIDs: taskMonitor.unconfirmedCompletionTaskIDs
    )
  }
}
