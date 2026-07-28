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
  private let requestIDGenerator: AppServerRequestIDGenerator
  private var taskMonitor: AppServerTaskMonitor
  private var quotaMonitor: AppServerQuotaMonitor
  private let confirmableQuotaResetDetector: ConfirmableQuotaResetDetector
  private let requiresSharedRuntimeEvidence: Bool
  private var sharedRuntimeValidated: Bool
  private var hasStarted = false
  private var observationTime = Date()
  private var displayLayout: BeaconDisplayLayout?
  private var beaconAnchor: BeaconAnchor?
  private var showTaskTitles: Bool

  public var autoConfirmCondition: (() -> Bool)?

  public init(
    requiresSharedRuntimeEvidence: Bool = false,
    initialBeaconAnchor: BeaconAnchor? = nil,
    initialBeaconSize: BeaconSize = .standard,
    showTaskTitles: Bool = false,
    quotaResetBaselineStore: QuotaResetBaselineStore = .init()
  ) {
    let requestIDGenerator = AppServerRequestIDGenerator()
    self.requestIDGenerator = requestIDGenerator
    taskMonitor = AppServerTaskMonitor(requestIDGenerator: requestIDGenerator)
    quotaMonitor = AppServerQuotaMonitor(requestIDGenerator: requestIDGenerator)
    confirmableQuotaResetDetector = ConfirmableQuotaResetDetector(store: quotaResetBaselineStore)
    self.requiresSharedRuntimeEvidence = requiresSharedRuntimeEvidence
    sharedRuntimeValidated = !requiresSharedRuntimeEvidence
    beaconAnchor = initialBeaconAnchor
    viewState.size = initialBeaconSize
    self.showTaskTitles = showTaskTitles
    viewState.showTaskTitles = showTaskTitles
  }

  public func setShowTaskTitles(_ enabled: Bool) {
    showTaskTitles = enabled
    viewState.showTaskTitles = enabled
    updateHoverDetail()
  }

  public func start() {
    guard !hasStarted else {
      return
    }

    hasStarted = true
    viewState.present(.monitoringUnavailable)
    updateHoverDetail()
    effects.append(.showBeacon)
  }

  public func handle(_ event: ApplicationEvent) {
    switch event {
    case .task(.monitoringConnectionEstablished(let protocolCompatible)):
      sharedRuntimeValidated = !requiresSharedRuntimeEvidence
      presentTaskStatus(
        taskMonitor.connectionEstablished(
          protocolCompatible: protocolCompatible,
          observedAt: observationTime
        )
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
      updateHoverDetail()
    case .task(.monitoringObservationBecameStale):
      presentTaskStatus(taskMonitor.observationBecameStale())
      quotaMonitor.observationBecameStale()
      viewState.quotaTrack = quotaTrackState(from: quotaMonitor.accountQuota)
      updateHoverDetail()
    case .task(.monitoringSnapshotRequested):
      presentTaskStatus(
        sharedRuntimeValidated
          ? taskMonitor.snapshotRequested(observedAt: observationTime)
          : .monitoringUnavailable
      )
    case .task(.quotaSnapshotRequested):
      quotaMonitor.snapshotRequested()
    case .task(.appServerMessage(let message)):
      let completionsBefore = taskMonitor.unconfirmedCompletionTaskIDs
      let quotaHandled = quotaMonitor.handle(
        message: message, observedAt: observationTime)
      if !quotaHandled {
        _ = taskMonitor.handle(message: message, observedAt: observationTime)
      }
      if quotaHandled {
        viewState.quotaTrack = quotaTrackState(from: quotaMonitor.accountQuota)
        updateHoverDetail()
        for accountContext in quotaMonitor.drainAccountContextObservations() {
          confirmableQuotaResetDetector.clearBaselineIfAccountChanged(to: accountContext)
        }
        if quotaMonitor.drainBaselineInvalidation() {
          confirmableQuotaResetDetector.clearBaseline()
        }
        // Drain reset events detected by the quota monitor and surface them
        // in the view state for the app delegate to process.
        let resets = quotaMonitor.drainResetEvents()
        if !resets.isEmpty {
          viewState.pendingResetEvents.append(contentsOf: resets)
        }
        let confirmableResets = quotaMonitor.drainBaselineObservations().compactMap {
          confirmableQuotaResetDetector.observe($0)
        }
        if !confirmableResets.isEmpty {
          viewState.pendingResetEvents.append(contentsOf: confirmableResets)
        }
      }
      let newCompletions = taskMonitor.unconfirmedCompletionTaskIDs.subtracting(
        completionsBefore)
      if !newCompletions.isEmpty,
        let policy = autoConfirmCondition,
        sharedRuntimeValidated,
        policy()
      {
        taskMonitor.confirmCompletions(newCompletions)
      }
      presentTaskStatus(
        sharedRuntimeValidated ? taskMonitor.status : .monitoringUnavailable
      )
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
    case .system(.globalHotKeyPressed):
      viewState.isVisible.toggle()
      effects.append(viewState.isVisible ? .showBeacon : .hideBeacon)
    case .system(.displayLayoutChanged(let layout)):
      updateBeaconPlacement(for: layout)
    case .user(.beaconActivated):
      let navigationTarget: String?
      switch taskMonitor.status {
      case .waitingForYou:
        navigationTarget = taskMonitor.waitingTasks.first?.threadID
      case .completed:
        navigationTarget = taskMonitor.unconfirmedCompletionTaskIDs.first
      case .working:
        navigationTarget = taskMonitor.workingTaskIDs.first
      default:
        navigationTarget = nil
      }
      let confirmSnapshot = taskMonitor.unconfirmedCompletionTaskIDs
      taskMonitor.confirmCompletions(confirmSnapshot)
      presentTaskStatus(
        sharedRuntimeValidated ? taskMonitor.status : .monitoringUnavailable
      )
      effects.append(.activateCodex(threadID: navigationTarget))
    case .user(.beaconDragEnded(let displayIdentifier, let frame)):
      guard let display = displayLayout?.display(identifier: displayIdentifier) else {
        return
      }

      beaconAnchor = BeaconPlacementResolver.anchor(forDraggedFrame: frame, on: display)
      presentBeaconPlacement(on: display)
    case .user(.beaconSizeSelected(let size)):
      guard viewState.size != size else {
        return
      }

      viewState.size = size
      if let displayLayout {
        updateBeaconPlacement(for: displayLayout)
      }
    }
  }

  public func drainEffects() -> [BeaconEffect] {
    defer { effects.removeAll() }
    return effects
  }

  public func drainAppServerRequests() -> [AppServerRequest] {
    taskMonitor.drainRequests() + quotaMonitor.drainRequests()
  }

  /// Drains pending reset events from the view state. The caller (app
  /// delegate) uses these to trigger notifications and border pulse.
  public func drainViewResetEvents() -> [QuotaResetEvent] {
    return viewState.drainResetEvents()
  }

  /// Clears the temporary reset message if it has expired.
  @discardableResult
  public func clearExpiredResetMessage(now: Date) -> Bool {
    viewState.clearExpiredResetMessage(now: now)
  }

  /// Applies a temporary reset message to the view state.
  public func applyResetMessage(_ message: String, expiresAt: Date) {
    viewState.setResetMessage(message, expiresAt: expiresAt)
  }

  private func presentTaskStatus(_ status: BeaconStatus) {
    viewState.present(
      status,
      waitingTasks: taskMonitor.waitingTasks,
      unconfirmedCompletionTaskIDs: taskMonitor.unconfirmedCompletionTaskIDs
    )
    updateHoverDetail()
  }

  private func updateBeaconPlacement(for layout: BeaconDisplayLayout) {
    displayLayout = layout
    guard let primaryDisplay = layout.display(identifier: layout.primaryDisplayIdentifier) else {
      return
    }

    let anchor = beaconAnchor ?? BeaconPlacementResolver.defaultAnchor(
      in: primaryDisplay,
      size: viewState.size
    )
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

    let placement = BeaconPlacementResolver.placement(
      for: beaconAnchor,
      on: display,
      size: viewState.size
    )
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

  private func updateHoverDetail() {
    let titles = taskMonitor.allTaskTitles
    let sessionIds = taskMonitor.allTaskSessionIds
    let waitingTasks = taskMonitor.waitingTasks
    let workingIDs = taskMonitor.workingTaskIDs
    let completedIDs = taskMonitor.unconfirmedCompletionTaskIDs
    let status = sharedRuntimeValidated ? taskMonitor.status : .monitoringUnavailable
    let quota = quotaMonitor.accountQuota

    var tasks: [HoverTaskEntry] = []
    for waiting in waitingTasks {
      tasks.append(HoverTaskEntry(
        threadID: waiting.threadID,
        title: titles[waiting.threadID] ?? waiting.title,
        sessionId: sessionIds[waiting.threadID],
        state: .waitingForYou
      ))
    }
    for id in workingIDs {
      guard !waitingTasks.contains(where: { $0.threadID == id }) else { continue }
      tasks.append(HoverTaskEntry(
        threadID: id, title: titles[id], sessionId: sessionIds[id], state: .working))
    }
    for id in completedIDs {
      tasks.append(HoverTaskEntry(
        threadID: id, title: titles[id], sessionId: sessionIds[id], state: .completed))
    }

    let taskError: String? =
      status == .monitoringUnavailable ? "任务监测不可用" : nil
    let quotaError: String? =
      !quota.isAvailable ? "额度信息不可用" : nil

    viewState.hoverDetail = HoverDetailState(
      status: status,
      workingCount: workingIDs.count,
      waitingCount: waitingTasks.count,
      completedCount: completedIDs.count,
      tasks: tasks,
      quotaWindows: quota.windows,
      lastUpdatedAt: viewState.lastUpdatedAt,
      taskError: taskError,
      quotaError: quotaError,
      showTaskTitles: showTaskTitles
    )
  }
}
