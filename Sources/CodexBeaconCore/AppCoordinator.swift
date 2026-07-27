import Foundation

public enum BeaconEffect: Equatable, Sendable {
  case showBeacon
  case hideBeacon
  case activateCodex(threadID: String?)
  case placeBeacon(BeaconPlacement)
}

@MainActor
public final class AppCoordinator {
  public private(set) var viewState = BeaconViewState.idle

  private var effects: [BeaconEffect] = []
  private var taskMonitor = AppServerTaskMonitor()
  private var quotaMonitor = AppServerQuotaMonitor()
  private let requiresSharedRuntimeEvidence: Bool
  private var sharedRuntimeValidated: Bool
  private var hasStarted = false
  private var observationTime = Date()
  private var displayLayout: BeaconDisplayLayout?
  private var beaconAnchor: BeaconAnchor?

  public init(
    requiresSharedRuntimeEvidence: Bool = false,
    initialBeaconAnchor: BeaconAnchor? = nil
  ) {
    self.requiresSharedRuntimeEvidence = requiresSharedRuntimeEvidence
    sharedRuntimeValidated = !requiresSharedRuntimeEvidence
    beaconAnchor = initialBeaconAnchor
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
      quotaMonitor.connectionEstablished()
    case .task(.monitoringRuntimeValidated):
      sharedRuntimeValidated = true
      presentTaskStatus(taskMonitor.status)
    case .task(.monitoringConnectionFailed):
      sharedRuntimeValidated = false
      presentTaskStatus(taskMonitor.connectionFailed())
      quotaMonitor.connectionFailed()
      viewState.quotaTrack = quotaTrackState(from: quotaMonitor.accountQuota)
    case .task(.monitoringObservationBecameStale):
      presentTaskStatus(taskMonitor.observationBecameStale())
      quotaMonitor.observationBecameStale()
      viewState.quotaTrack = quotaTrackState(from: quotaMonitor.accountQuota)
    case .task(.monitoringSnapshotRequested):
      presentTaskStatus(
        sharedRuntimeValidated
          ? taskMonitor.snapshotRequested()
          : .monitoringUnavailable
      )
    case .task(.appServerMessage(let message)):
      let quotaHandled = quotaMonitor.handle(
        message: message, observedAt: observationTime)
      let status: BeaconStatus
      if quotaHandled {
        status = taskMonitor.status
      } else {
        status = taskMonitor.handle(message: message, observedAt: observationTime)
      }
      if quotaHandled {
        viewState.quotaTrack = quotaTrackState(from: quotaMonitor.accountQuota)
      }
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
    case .system(.displayLayoutChanged(let layout)):
      updateBeaconPlacement(for: layout)
    case .user(.beaconActivated):
      let waitingThreadID = taskMonitor.waitingTasks.first?.threadID
      taskMonitor.confirmCompletions()
      presentTaskStatus(
        sharedRuntimeValidated ? taskMonitor.status : .monitoringUnavailable
      )
      effects.append(.activateCodex(threadID: waitingThreadID))
    case .user(.beaconDragEnded(let displayIdentifier, let frame)):
      guard let display = displayLayout?.display(identifier: displayIdentifier) else {
        return
      }

      beaconAnchor = BeaconPlacementResolver.anchor(forDraggedFrame: frame, on: display)
      presentBeaconPlacement(on: display)
    }
  }

  public func drainEffects() -> [BeaconEffect] {
    defer { effects.removeAll() }
    return effects
  }

  public func drainAppServerRequests() -> [AppServerRequest] {
    taskMonitor.drainRequests() + quotaMonitor.drainRequests()
  }

  private func presentTaskStatus(_ status: BeaconStatus) {
    viewState.present(
      status,
      waitingTasks: taskMonitor.waitingTasks,
      unconfirmedCompletionTaskIDs: taskMonitor.unconfirmedCompletionTaskIDs
    )
  }

  private func updateBeaconPlacement(for layout: BeaconDisplayLayout) {
    displayLayout = layout
    guard let primaryDisplay = layout.display(identifier: layout.primaryDisplayIdentifier) else {
      return
    }

    let anchor = beaconAnchor ?? BeaconPlacementResolver.defaultAnchor(in: primaryDisplay)
    let destination = layout.display(identifier: anchor.displayIdentifier) ?? primaryDisplay
    let shouldMigrate = destination.identifier != anchor.displayIdentifier
    beaconAnchor = shouldMigrate
      ? BeaconAnchor(
        displayIdentifier: destination.identifier,
        edge: anchor.edge,
        alongEdgeOffset: anchor.alongEdgeOffset
      )
      : anchor

    presentBeaconPlacement(on: destination)
  }

  private func presentBeaconPlacement(on display: BeaconDisplay) {
    guard let beaconAnchor else {
      return
    }

    let placement = BeaconPlacementResolver.placement(for: beaconAnchor, on: display)
    self.beaconAnchor = placement.anchor
    viewState.orientation = placement.anchor.edge.orientation
    effects.append(.placeBeacon(placement))
  }

  private func quotaTrackState(from quota: AccountQuotaState) -> QuotaTrackState {
    guard quota.isAvailable, let selected = quota.selectedWindow else {
      return QuotaTrackState(style: .dashed)
    }
    let fill = max(0, min(1, selected.remainingPercentage / 100))
    return QuotaTrackState(
      style: .gauge,
      fillFraction: fill,
      detailWindows: quota.windows
    )
  }
}
