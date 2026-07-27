import Foundation
import Testing

@testable import CodexBeaconCore

@MainActor
struct AccountQuotaScenarioTests {
  private static let observationTime = Date(timeIntervalSince1970: 1_753_353_600)

  // MARK: - Snapshot and sparse updates

  @Test("full snapshot on connection populates all quota windows")
  func fullSnapshotPopulatesAllWindows() {
    let coordinator = AppCoordinator()

    coordinator.handle(
      .task(.monitoringConnectionEstablished(protocolCompatible: true)))
    let snapshotRequest = coordinator.drainAppServerRequests().last

    #expect(snapshotRequest?.method == "account/rateLimits/read")

    coordinator.handle(
      .task(
        .appServerMessage("""
          {"id":\(snapshotRequest!.id),"result":{"rateLimits":{"5h":{"durationSeconds":18000,"usedPercent":75},"7d":{"durationSeconds":604800,"usedPercent":30}}}}
          """))
    )

    let quota = coordinator.viewState.quotaTrack
    #expect(quota.style == .gauge)
    #expect(quota.detailWindows.count == 2)
    #expect(quota.detailWindows.map(\.windowKey).sorted() == ["5h", "7d"])
    #expect(coordinator.viewState.status == .monitoringUnavailable)
  }

  @Test("sparse update preserves field values from previous state for unchanged windows")
  func sparseUpdatePreservesFieldsFromPreviousState() {
    let coordinator = AppCoordinator()
    populateQuotaSnapshot(
      coordinator,
      windows: [
        "5h": (18000, 75),
        "7d": (604800, 30),
      ])

    // Sparse update replaces the window set but merges fields with previous state.
    // Both windows are included; 7d lacks durationSeconds so it reuses the prior value.
    coordinator.handle(
      .task(
        .appServerMessage("""
          {"method":"account/rateLimits/updated","params":{"rateLimits":{"5h":{"durationSeconds":18000,"usedPercent":90},"7d":{"usedPercent":50}}}}
          """))
    )

    let quota = coordinator.viewState.quotaTrack
    #expect(quota.style == .gauge)
    #expect(quota.detailWindows.count == 2)
    let fiveHour = quota.detailWindows.first { $0.windowKey == "5h" }
    #expect(fiveHour?.usedPercentage == 90)
    #expect(fiveHour?.remainingPercentage == 10)
    let sevenDay = quota.detailWindows.first { $0.windowKey == "7d" }
    #expect(sevenDay?.usedPercentage == 50)
    #expect(sevenDay?.durationSeconds == 604800)
  }

  // MARK: - Shortest window selection

  @Test("selects the shortest valid window, not assuming a fixed period")
  func selectsShortestWindow() {
    let coordinator = AppCoordinator()
    populateQuotaSnapshot(
      coordinator,
      windows: [
        "30m": (1800, 60),
        "5h": (18000, 45),
        "7d": (604800, 20),
      ])

    let quota = coordinator.viewState.quotaTrack
    #expect(quota.style == .gauge)
    let fillFor30m = 0.4  // 100 - 60 = 40%
    #expect(abs(quota.fillFraction - fillFor30m) < 0.01)
  }

  @Test("week-only window is selected as the sole window")
  func weekOnlyWindowSelected() {
    let coordinator = AppCoordinator()
    populateQuotaSnapshot(
      coordinator,
      windows: [
        "7d": (604800, 15),
      ])

    let quota = coordinator.viewState.quotaTrack
    #expect(quota.style == .gauge)
    #expect(quota.detailWindows.count == 1)
    #expect(abs(quota.fillFraction - 0.85) < 0.01)
    #expect(quota.detailWindows.first?.windowKey == "7d")
  }

  // MARK: - Remaining percentage and safe degradation

  @Test("remaining percentage converts from service used percentage")
  func remainingPercentageFromUsedPercentage() {
    let coordinator = AppCoordinator()
    populateQuotaSnapshot(
      coordinator,
      windows: [
        "5h": (18000, 0),
      ])

    let quota = coordinator.viewState.quotaTrack
    #expect(abs(quota.fillFraction - 1.0) < 0.01)

    coordinator.handle(
      .task(
        .appServerMessage("""
          {"method":"account/rateLimits/updated","params":{"rateLimits":{"5h":{"durationSeconds":18000,"usedPercent":100}}}}
          """))
    )
    #expect(abs(coordinator.viewState.quotaTrack.fillFraction - 0.0) < 0.01)
  }

  @Test("safe degrades when duration, reset time, or window data is missing")
  func safeDegradationOnMissingFields() {
    let coordinator = AppCoordinator()
    populateQuotaSnapshot(
      coordinator,
      windows: [
        "5h": (18000, 75),
      ])

    // Notification includes 5h (to keep it in the set) plus a new
    // "partial" window missing its duration. The partial window has
    // duration 0 so it is excluded from shortest-window selection.
    coordinator.handle(
      .task(
        .appServerMessage("""
          {"method":"account/rateLimits/updated","params":{"rateLimits":{"5h":{"durationSeconds":18000,"usedPercent":75},"partial":{"usedPercent":50}}}}
          """))
    )

    let quota = coordinator.viewState.quotaTrack
    #expect(quota.style == .gauge)
    let partialWindow = quota.detailWindows.first { $0.windowKey == "partial" }
    #expect(partialWindow?.durationSeconds == 0)
    #expect(partialWindow?.remainingPercentage == 50)
    let fiveHour = quota.detailWindows.first { $0.windowKey == "5h" }
    #expect(fiveHour != nil)
    #expect(fiveHour?.durationSeconds == 18000)
    // 5h is the only valid window (partial has no duration), so it's selected
    #expect(abs(quota.fillFraction - 0.25) < 0.01)
  }

  // MARK: - Window add/remove auto-switch

  @Test("switches to next shortest when current shortest window disappears")
  func switchesToNextShortestOnDisappearance() {
    let coordinator = AppCoordinator()
    populateQuotaSnapshot(
      coordinator,
      windows: [
        "1h": (3600, 50),
        "5h": (18000, 30),
      ])

    #expect(abs(coordinator.viewState.quotaTrack.fillFraction - 0.5) < 0.01)

    // Sparse update that omits the 1h window (simulating its removal)
    coordinator.handle(
      .task(
        .appServerMessage("""
          {"method":"account/rateLimits/updated","params":{"rateLimits":{"5h":{"durationSeconds":18000,"usedPercent":30}}}}
          """))
    )

    let quota = coordinator.viewState.quotaTrack
    #expect(quota.style == .gauge)
    #expect(abs(quota.fillFraction - 0.7) < 0.01)
  }

  @Test("restores shortest window when it reappears")
  func restoresShortestWindowOnReappearance() {
    let coordinator = AppCoordinator()
    populateQuotaSnapshot(
      coordinator,
      windows: [
        "1h": (3600, 40),
        "5h": (18000, 20),
      ])

    #expect(abs(coordinator.viewState.quotaTrack.fillFraction - 0.6) < 0.01)

    // 1h window disappears
    coordinator.handle(
      .task(
        .appServerMessage("""
          {"method":"account/rateLimits/updated","params":{"rateLimits":{"5h":{"durationSeconds":18000,"usedPercent":20}}}}
          """))
    )
    #expect(abs(coordinator.viewState.quotaTrack.fillFraction - 0.8) < 0.01)

    // 1h window reappears
    coordinator.handle(
      .task(
        .appServerMessage("""
          {"method":"account/rateLimits/updated","params":{"rateLimits":{"1h":{"durationSeconds":3600,"usedPercent":90}}}}
          """))
    )

    #expect(abs(coordinator.viewState.quotaTrack.fillFraction - 0.1) < 0.01)
  }

  // MARK: - Unavailable / dashed state

  @Test("quota unavailable shows dashed style without changing Codex status")
  func quotaUnavailableShowsDashed() {
    let coordinator = AppCoordinator()
    coordinator.start()

    #expect(coordinator.viewState.quotaTrack.style == .neutral)

    coordinator.handle(
      .task(.monitoringConnectionEstablished(protocolCompatible: true)))
    let allRequests = coordinator.drainAppServerRequests()
    let snapshotRequest = allRequests.first { $0.method == "account/rateLimits/read" }

    coordinator.handle(
      .task(
        .appServerMessage("""
          {"id":\(snapshotRequest!.id),"result":{"rateLimits":{"5h":{"durationSeconds":18000,"usedPercent":75}}}}
          """))
    )

    #expect(coordinator.viewState.quotaTrack.style == .gauge)

    coordinator.handle(.task(.monitoringConnectionFailed))

    #expect(coordinator.viewState.quotaTrack.style == .dashed)
    #expect(coordinator.viewState.status == .monitoringUnavailable)
  }

  // MARK: - Task monitoring independence

  @Test("quota read failure does not affect task monitoring")
  func quotaReadFailureIndependentFromTaskMonitoring() {
    let coordinator = AppCoordinator()

    coordinator.handle(
      .task(.monitoringConnectionEstablished(protocolCompatible: true)))
    let allRequests = coordinator.drainAppServerRequests()
    let loadedListRequest = allRequests.first { $0.method == "thread/loaded/list" }
    let snapshotRequest = allRequests.first { $0.method == "account/rateLimits/read" }

    // Task snapshot completes successfully
    coordinator.handle(
      .task(
        .appServerMessage("""
          {"id":\(loadedListRequest!.id),"result":{"data":["thread-1"]}}
          """))
    )
    let readRequest = coordinator.drainAppServerRequests().first!
    coordinator.handle(
      .task(
        .appServerMessage("""
          {"id":\(readRequest.id),"result":{"thread":{"id":"thread-1","source":"vscode","ephemeral":false,"parentThreadId":null,"status":{"type":"active","activeFlags":[]}}}}
          """))
    )

    #expect(coordinator.viewState.status == .working)

    // Quota snapshot fails with an error
    coordinator.handle(
      .task(
        .appServerMessage("""
          {"id":\(snapshotRequest!.id),"error":{"code":-32000,"message":"rate limits not available"}}
          """))
    )

    // Task status still shows working
    #expect(coordinator.viewState.status == .working)
    // Quota track falls back to dashed since no data was ever received
    #expect(coordinator.viewState.quotaTrack.style == .dashed)
  }

  @Test("task monitoring failure does not affect quota display")
  func taskMonitoringFailureIndependentFromQuota() {
    let coordinator = AppCoordinator()

    coordinator.handle(
      .task(.monitoringConnectionEstablished(protocolCompatible: true)))
    let allRequests = coordinator.drainAppServerRequests()
    let snapshotRequest = allRequests.first { $0.method == "account/rateLimits/read" }

    coordinator.handle(
      .task(
        .appServerMessage("""
          {"id":\(snapshotRequest!.id),"result":{"rateLimits":{"5h":{"durationSeconds":18000,"usedPercent":25}}}}
          """))
    )

    #expect(coordinator.viewState.quotaTrack.style == .gauge)
    #expect(abs(coordinator.viewState.quotaTrack.fillFraction - 0.75) < 0.01)

    coordinator.handle(.task(.monitoringObservationBecameStale))

    #expect(coordinator.viewState.status == .monitoringUnavailable)
    #expect(coordinator.viewState.quotaTrack.style == .dashed)
  }

  // MARK: - Dynamic window add/remove

  @Test("dynamic window additions and removals are correctly reflected")
  func dynamicWindowAddRemove() {
    let coordinator = AppCoordinator()

    // Initial: only weekly window
    coordinator.handle(
      .task(.monitoringConnectionEstablished(protocolCompatible: true)))
    let snapshotRequest = coordinator.drainAppServerRequests().last!
    coordinator.handle(
      .task(
        .appServerMessage("""
          {"id":\(snapshotRequest.id),"result":{"rateLimits":{"7d":{"durationSeconds":604800,"usedPercent":30}}}}
          """))
    )
    #expect(coordinator.viewState.quotaTrack.detailWindows.count == 1)

    // A new 5h window appears alongside the existing 7d
    coordinator.handle(
      .task(
        .appServerMessage("""
          {"method":"account/rateLimits/updated","params":{"rateLimits":{"7d":{"durationSeconds":604800,"usedPercent":30},"5h":{"durationSeconds":18000,"usedPercent":80}}}}
          """))
    )
    #expect(coordinator.viewState.quotaTrack.detailWindows.count == 2)
    #expect(abs(coordinator.viewState.quotaTrack.fillFraction - 0.2) < 0.01)

    // A new 1h window appears — auto-switch to shortest
    coordinator.handle(
      .task(
        .appServerMessage("""
          {"method":"account/rateLimits/updated","params":{"rateLimits":{"7d":{"durationSeconds":604800,"usedPercent":30},"5h":{"durationSeconds":18000,"usedPercent":80},"1h":{"durationSeconds":3600,"usedPercent":10}}}}
          """))
    )
    #expect(coordinator.viewState.quotaTrack.detailWindows.count == 3)
    #expect(abs(coordinator.viewState.quotaTrack.fillFraction - 0.9) < 0.01)
  }

  // MARK: - Quota message does not interfere with task notifications

  @Test("a quota notification does not trigger task state transitions")
  func quotaNotificationIndependentFromTaskState() {
    let coordinator = AppCoordinator()

    coordinator.handle(
      .task(.monitoringConnectionEstablished(protocolCompatible: true)))
    let allRequests = coordinator.drainAppServerRequests()
    let loadedListRequest = allRequests.first { $0.method == "thread/loaded/list" }
    let snapshotRequest = allRequests.first { $0.method == "account/rateLimits/read" }

    coordinator.handle(
      .task(
        .appServerMessage("""
          {"id":\(loadedListRequest!.id),"result":{"data":[]}}
          """))
    )
    #expect(coordinator.viewState.status == .idle)

    // Process quota snapshot
    coordinator.handle(
      .task(
        .appServerMessage("""
          {"id":\(snapshotRequest!.id),"result":{"rateLimits":{"5h":{"durationSeconds":18000,"usedPercent":50}}}}
          """))
    )

    // Task status should still be idle
    #expect(coordinator.viewState.status == .idle)
    #expect(coordinator.viewState.quotaTrack.style == .gauge)

    // A quota notification should not affect task status
    coordinator.handle(
      .task(
        .appServerMessage("""
          {"method":"account/rateLimits/updated","params":{"rateLimits":{"5h":{"durationSeconds":18000,"usedPercent":90}}}}
          """))
    )

    #expect(coordinator.viewState.status == .idle)
    #expect(abs(coordinator.viewState.quotaTrack.fillFraction - 0.1) < 0.01)
  }

  @Test("quota uses a pending request then becomes available on notification before response")
  func quotaAvailableViaNotificationBeforeResponse() {
    let coordinator = AppCoordinator()

    coordinator.handle(
      .task(.monitoringConnectionEstablished(protocolCompatible: true)))
    _ = coordinator.drainAppServerRequests()

    // Notification arrives before the snapshot response
    coordinator.handle(
      .task(
        .appServerMessage("""
          {"method":"account/rateLimits/updated","params":{"rateLimits":{"5h":{"durationSeconds":18000,"usedPercent":60}}}}
          """))
    )

    #expect(coordinator.viewState.quotaTrack.style == .gauge)
    #expect(abs(coordinator.viewState.quotaTrack.fillFraction - 0.4) < 0.01)
  }

  // MARK: - Helpers

  private func populateQuotaSnapshot(
    _ coordinator: AppCoordinator,
    windows: [String: (TimeInterval, Double)],
    fileID: String = #fileID,
    filePath: String = #filePath,
    line: Int = #line,
    column: Int = #column
  ) {
    coordinator.handle(
      .task(.monitoringConnectionEstablished(protocolCompatible: true)))
    let allRequests = coordinator.drainAppServerRequests()
    let snapshotRequest = allRequests.first { $0.method == "account/rateLimits/read" }
    guard let request = snapshotRequest else {
      Issue.record("quota snapshot request was not drained", sourceLocation: .init(fileID: fileID, filePath: filePath, line: line, column: column))
      return
    }
    let entries = windows.map { key, pair in
      let (duration, used) = pair
      return "\"\(key)\":{\"durationSeconds\":\(duration),\"usedPercent\":\(used)}"
    }.joined(separator: ",")
    coordinator.handle(
      .task(
        .appServerMessage("""
          {"id":\(request.id),"result":{"rateLimits":{\(entries)}}}
          """))
    )
  }
}
