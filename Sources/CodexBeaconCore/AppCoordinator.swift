public enum BeaconEffect: Equatable, Sendable {
  case showBeacon
  case hideBeacon
}

@MainActor
public final class AppCoordinator {
  public private(set) var viewState = BeaconViewState.idle

  private var effects: [BeaconEffect] = []
  private var taskMonitor = AppServerTaskMonitor()
  private var hasStarted = false

  public init() {}

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
      viewState.present(
        taskMonitor.connectionEstablished(
          protocolCompatible: protocolCompatible
        )
      )
    case .task(.monitoringConnectionFailed):
      viewState.present(taskMonitor.connectionFailed())
    case .task(.monitoringObservationBecameStale):
      viewState.present(taskMonitor.observationBecameStale())
    case .task(.appServerMessage(let message)):
      viewState.present(taskMonitor.handle(message: message))
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
    taskMonitor.drainRequests()
  }
}
