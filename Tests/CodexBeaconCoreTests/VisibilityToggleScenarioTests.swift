import Foundation
import Testing

@testable import CodexBeaconCore

@MainActor
struct VisibilityToggleScenarioTests {
  @Test("visibility toggle hides and shows beacon without affecting task state")
  func visibilityTogglePreservesTaskState() {
    let coordinator = AppCoordinator()

    coordinator.handle(
      .task(.monitoringConnectionEstablished(protocolCompatible: true)))
    let loadedRequest = coordinator.drainAppServerRequests().first!
    coordinator.handle(
      .task(
        .appServerMessage(
          """
          {"id":\(loadedRequest.id),"result":{"data":["task-1"]}}
          """))
    )
    let readRequest = coordinator.drainAppServerRequests().first!
    coordinator.handle(
      .task(
        .appServerMessage(
          """
          {"id":\(readRequest.id),"result":{"thread":{"id":"task-1","source":"vscode","ephemeral":false,"parentThreadId":null,"status":{"type":"active","activeFlags":[]}}}}
          """))
    )

    #expect(coordinator.viewState.status == .working)
    #expect(coordinator.viewState.isVisible)

    // Hide beacon — task state must be preserved.
    coordinator.handle(.system(.visibilityChanged(false)))

    #expect(!coordinator.viewState.isVisible)
    #expect(coordinator.viewState.status == .working)
    #expect(coordinator.drainEffects() == [.hideBeacon])

    // Show beacon — task state still preserved.
    coordinator.handle(.system(.visibilityChanged(true)))

    #expect(coordinator.viewState.isVisible)
    #expect(coordinator.viewState.status == .working)
    #expect(coordinator.drainEffects() == [.showBeacon])
  }

  @Test("redundant visibility events are ignored without emitting effects")
  func redundantVisibilityEventsAreNoOps() {
    let coordinator = AppCoordinator()

    #expect(coordinator.viewState.isVisible)

    // Hide once.
    coordinator.handle(.system(.visibilityChanged(false)))
    #expect(coordinator.drainEffects() == [.hideBeacon])

    // Hide again — no effect.
    coordinator.handle(.system(.visibilityChanged(false)))
    #expect(coordinator.drainEffects().isEmpty)

    // Show once.
    coordinator.handle(.system(.visibilityChanged(true)))
    #expect(coordinator.drainEffects() == [.showBeacon])

    // Show again — no effect.
    coordinator.handle(.system(.visibilityChanged(true)))
    #expect(coordinator.drainEffects().isEmpty)
  }

  @Test("task events are processed and state updated while beacon is hidden")
  func taskEventsProcessedWhileHidden() {
    let coordinator = AppCoordinator()

    coordinator.handle(
      .task(.monitoringConnectionEstablished(protocolCompatible: true)))
    let loadedRequest = coordinator.drainAppServerRequests().first!
    coordinator.handle(
      .task(
        .appServerMessage(
          """
          {"id":\(loadedRequest.id),"result":{"data":["task-1"]}}
          """))
    )
    let readRequest = coordinator.drainAppServerRequests().first!
    coordinator.handle(
      .task(
        .appServerMessage(
          """
          {"id":\(readRequest.id),"result":{"thread":{"id":"task-1","source":"vscode","ephemeral":false,"parentThreadId":null,"status":{"type":"active","activeFlags":[]}}}}
          """))
    )

    #expect(coordinator.viewState.status == .working)

    // Hide beacon.
    coordinator.handle(.system(.visibilityChanged(false)))
    _ = coordinator.drainEffects()

    #expect(!coordinator.viewState.isVisible)

    // Task transitions to waiting-for-you while hidden.
    // The coordinator must still process the event and update state.
    coordinator.handle(
      .task(
        .appServerMessage(
          """
          {"method":"thread/status/changed","params":{"threadId":"task-1","status":{"type":"active","activeFlags":["waitingOnUserInput"]}}}
          """))
    )

    // State is updated even though the beacon is hidden.
    #expect(coordinator.viewState.status == .waitingForYou)
    #expect(!coordinator.viewState.isVisible)
  }

  @Test("view state reflects latest monitoring status after unhiding")
  func viewStateReflectsLatestStatusAfterUnhiding() {
    let coordinator = AppCoordinator()

    coordinator.handle(
      .task(.monitoringConnectionEstablished(protocolCompatible: true)))
    let loadedRequest = coordinator.drainAppServerRequests().first!
    coordinator.handle(
      .task(
        .appServerMessage(
          """
          {"id":\(loadedRequest.id),"result":{"data":["task-1"]}}
          """))
    )
    let readRequest = coordinator.drainAppServerRequests().first!
    coordinator.handle(
      .task(
        .appServerMessage(
          """
          {"id":\(readRequest.id),"result":{"thread":{"id":"task-1","source":"vscode","ephemeral":false,"parentThreadId":null,"status":{"type":"active","activeFlags":[]}}}}
          """))
    )

    #expect(coordinator.viewState.status == .working)

    // Hide.
    coordinator.handle(.system(.visibilityChanged(false)))
    _ = coordinator.drainEffects()

    // Status changes to waiting while hidden.
    coordinator.handle(
      .task(
        .appServerMessage(
          """
          {"method":"thread/status/changed","params":{"threadId":"task-1","status":{"type":"active","activeFlags":["waitingOnApproval"]}}}
          """))
    )

    #expect(coordinator.viewState.status == .waitingForYou)
    #expect(!coordinator.viewState.isVisible)

    // Unhide — panel content reflects the latest task status.
    coordinator.handle(.system(.visibilityChanged(true)))

    #expect(coordinator.viewState.isVisible)
    #expect(coordinator.viewState.status == .waitingForYou)
    #expect(coordinator.drainEffects() == [.showBeacon])
  }

  @Test("quota updates continue to be processed while beacon is hidden")
  func quotaUpdatesProcessedWhileHidden() {
    let coordinator = AppCoordinator()

    coordinator.handle(
      .task(.monitoringConnectionEstablished(protocolCompatible: true)))
    let allRequests = coordinator.drainAppServerRequests()
    let snapshotRequest = allRequests.first { $0.method == "account/rateLimits/read" }

    coordinator.handle(
      .task(
        .appServerMessage(
          """
          {"id":\(snapshotRequest!.id),"result":{"rateLimits":{"5h":{"durationSeconds":18000,"usedPercent":50}}}}
          """))
    )

    let initialQuota = coordinator.viewState.quotaTrack
    #expect(initialQuota.style == .gauge)
    #expect(abs(initialQuota.fillFraction - 0.5) < 0.01)

    // Hide beacon.
    coordinator.handle(.system(.visibilityChanged(false)))
    _ = coordinator.drainEffects()

    // Quota update arrives while hidden.
    coordinator.handle(
      .task(
        .appServerMessage(
          """
          {"method":"account/rateLimits/updated","params":{"rateLimits":{"5h":{"durationSeconds":18000,"usedPercent":90}}}}
          """))
    )

    // State reflects updated quota.
    let updatedQuota = coordinator.viewState.quotaTrack
    #expect(updatedQuota.style == .gauge)
    #expect(abs(updatedQuota.fillFraction - 0.1) < 0.01)
    #expect(!coordinator.viewState.isVisible)

    // Unhide — quota track reflects latest value.
    coordinator.handle(.system(.visibilityChanged(true)))

    let finalQuota = coordinator.viewState.quotaTrack
    #expect(finalQuota.style == .gauge)
    #expect(abs(finalQuota.fillFraction - 0.1) < 0.01)
    #expect(coordinator.viewState.isVisible)
  }

  @Test("beacon starts visible after application launch")
  func beaconStartsVisibleAfterLaunch() {
    let coordinator = AppCoordinator()

    coordinator.start()

    #expect(coordinator.viewState.isVisible)
    #expect(coordinator.drainEffects().contains(.showBeacon))
  }

  @Test("time events are processed and lastUpdatedAt advances while hidden")
  func timeEventsProcessedWhileHidden() {
    let coordinator = AppCoordinator()
    let observationTime = Date(timeIntervalSince1970: 1_753_344_000)

    coordinator.start()
    _ = coordinator.drainEffects()

    // Hide.
    coordinator.handle(.system(.visibilityChanged(false)))
    _ = coordinator.drainEffects()

    #expect(!coordinator.viewState.isVisible)

    // Time advances while hidden.
    coordinator.handle(.time(.advanced(to: observationTime)))

    #expect(coordinator.viewState.lastUpdatedAt == observationTime)
    #expect(!coordinator.viewState.isVisible)

    // Unhide — time is still tracked.
    coordinator.handle(.system(.visibilityChanged(true)))

    #expect(coordinator.viewState.isVisible)
    #expect(coordinator.viewState.lastUpdatedAt == observationTime)
  }
}
