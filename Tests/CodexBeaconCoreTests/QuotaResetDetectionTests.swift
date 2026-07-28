import Foundation
import Testing

@testable import CodexBeaconCore

@MainActor
struct QuotaResetDetectionTests {
  private static let observationTime = Date(timeIntervalSince1970: 1_753_353_600)

  // MARK: - Confirmed reset (Beacon's own snapshot)

  @Test("confirmed reset when snapshot shows usage drop to near zero")
  func confirmedResetOnSnapshotUsageDrop() {
    let coordinator = AppCoordinator()
    let start = Self.observationTime
    coordinator.handle(.time(.advanced(to: start)))
    coordinator.handle(.task(.monitoringConnectionEstablished(protocolCompatible: true)))
    let initialRequest = coordinator.drainAppServerRequests().last!

    // Initial snapshot: 75% used → meaningful usage
    coordinator.handle(
      .task(.appServerMessage("""
        {"id":\(initialRequest.id),"result":{"rateLimits":{"5h":{"durationSeconds":18000,"usedPercent":75}}}}
        """))
    )
    #expect(coordinator.viewState.quotaTrack.style == .gauge)

    // Second snapshot: used drops to 0 → confirmed reset
    coordinator.handle(.task(.quotaSnapshotRequested))
    let refreshRequest = coordinator.drainAppServerRequests().first!
    coordinator.handle(
      .task(.appServerMessage("""
        {"id":\(refreshRequest.id),"result":{"rateLimits":{"5h":{"durationSeconds":18000,"usedPercent":0}}}}
        """))
    )

    let resetEvents = coordinator.drainViewResetEvents()
    #expect(resetEvents.count == 1)
    #expect(resetEvents[0].kind == .confirmed)
    #expect(resetEvents[0].windowKeys == ["5h"])
  }

  @Test("no confirmed reset when usage drops but was never meaningfully high")
  func noConfirmedResetWhenUsageWasLow() {
    let coordinator = AppCoordinator()
    let start = Self.observationTime
    coordinator.handle(.time(.advanced(to: start)))
    coordinator.handle(.task(.monitoringConnectionEstablished(protocolCompatible: true)))
    let initialRequest = coordinator.drainAppServerRequests().last!

    // Initial snapshot: only 5% used (below meaningful threshold of 10%)
    coordinator.handle(
      .task(.appServerMessage("""
        {"id":\(initialRequest.id),"result":{"rateLimits":{"5h":{"durationSeconds":18000,"usedPercent":5}}}}
        """))
    )

    // Second snapshot: drops to 0 but was never meaningfully high
    coordinator.handle(.task(.quotaSnapshotRequested))
    let refreshRequest = coordinator.drainAppServerRequests().first!
    coordinator.handle(
      .task(.appServerMessage("""
        {"id":\(refreshRequest.id),"result":{"rateLimits":{"5h":{"durationSeconds":18000,"usedPercent":0}}}}
        """))
    )

    let resetEvents = coordinator.drainViewResetEvents()
    #expect(resetEvents.isEmpty)
  }

  @Test("no confirmed reset when usage is still above reset threshold")
  func noConfirmedResetWhenUsageStillHigh() {
    let coordinator = AppCoordinator()
    let start = Self.observationTime
    coordinator.handle(.time(.advanced(to: start)))
    coordinator.handle(.task(.monitoringConnectionEstablished(protocolCompatible: true)))
    let initialRequest = coordinator.drainAppServerRequests().last!

    coordinator.handle(
      .task(.appServerMessage("""
        {"id":\(initialRequest.id),"result":{"rateLimits":{"5h":{"durationSeconds":18000,"usedPercent":80}}}}
        """))
    )

    coordinator.handle(.task(.quotaSnapshotRequested))
    let refreshRequest = coordinator.drainAppServerRequests().first!
    coordinator.handle(
      .task(.appServerMessage("""
        {"id":\(refreshRequest.id),"result":{"rateLimits":{"5h":{"durationSeconds":18000,"usedPercent":30}}}}
        """))
    )

    let resetEvents = coordinator.drainViewResetEvents()
    #expect(resetEvents.isEmpty)
  }

  // MARK: - Inferred reset (notification from other clients)

  @Test("inferred reset when notification shows usage drop AND reset boundary forward")
  func inferredResetWithConsistentEvidence() {
    let coordinator = AppCoordinator()
    let start = Self.observationTime
    coordinator.handle(.time(.advanced(to: start)))
    coordinator.handle(.task(.monitoringConnectionEstablished(protocolCompatible: true)))
    let initialRequest = coordinator.drainAppServerRequests().last!

    // Initial snapshot with resetAt in the past
    let oldResetTime = start.addingTimeInterval(-3600)
    let oldResetTimestamp = Int(oldResetTime.timeIntervalSince1970)
    coordinator.handle(
      .task(.appServerMessage("""
        {"id":\(initialRequest.id),"result":{"rateLimits":{"5h":{"durationSeconds":18000,"usedPercent":80,"resetsAt":\(oldResetTimestamp)}}}}
        """))
    )
    #expect(coordinator.viewState.quotaTrack.style == .gauge)

    // Notification from other client: used drops to 0 AND resetAt moves forward
    let newResetTime = start.addingTimeInterval(18000)
    let newResetTimestamp = Int(newResetTime.timeIntervalSince1970)
    coordinator.handle(
      .task(.appServerMessage("""
        {"method":"account/rateLimits/updated","params":{"rateLimits":{"5h":{"durationSeconds":18000,"usedPercent":0,"resetsAt":\(newResetTimestamp)}}}}
        """))
    )

    let resetEvents = coordinator.drainViewResetEvents()
    #expect(resetEvents.count == 1)
    #expect(resetEvents[0].kind == .inferred)
    #expect(resetEvents[0].windowKeys == ["5h"])
  }

  @Test("no inferred reset when usage drops but reset boundary does not move forward")
  func noInferredResetWhenBoundaryDoesNotMove() {
    let coordinator = AppCoordinator()
    let start = Self.observationTime
    coordinator.handle(.time(.advanced(to: start)))
    coordinator.handle(.task(.monitoringConnectionEstablished(protocolCompatible: true)))
    let initialRequest = coordinator.drainAppServerRequests().last!

    let resetTimestamp = Int(start.addingTimeInterval(18000).timeIntervalSince1970)
    coordinator.handle(
      .task(.appServerMessage("""
        {"id":\(initialRequest.id),"result":{"rateLimits":{"5h":{"durationSeconds":18000,"usedPercent":80,"resetsAt":\(resetTimestamp)}}}}
        """))
    )

    // Notification: used drops but resetAt is same (not forward) → no inferred reset
    coordinator.handle(
      .task(.appServerMessage("""
        {"method":"account/rateLimits/updated","params":{"rateLimits":{"5h":{"durationSeconds":18000,"usedPercent":0,"resetsAt":\(resetTimestamp)}}}}
        """))
    )

    let resetEvents = coordinator.drainViewResetEvents()
    #expect(resetEvents.isEmpty)
  }

  // MARK: - Multiple windows

  @Test("confirmed reset detects multiple windows simultaneously")
  func confirmedResetMultipleWindows() {
    let coordinator = AppCoordinator()
    let start = Self.observationTime
    coordinator.handle(.time(.advanced(to: start)))
    coordinator.handle(.task(.monitoringConnectionEstablished(protocolCompatible: true)))
    let initialRequest = coordinator.drainAppServerRequests().last!

    coordinator.handle(
      .task(.appServerMessage("""
        {"id":\(initialRequest.id),"result":{"rateLimits":{"5h":{"durationSeconds":18000,"usedPercent":80},"7d":{"durationSeconds":604800,"usedPercent":50}}}}
        """))
    )

    // Both windows drop to near zero
    coordinator.handle(.task(.quotaSnapshotRequested))
    let refreshRequest = coordinator.drainAppServerRequests().first!
    coordinator.handle(
      .task(.appServerMessage("""
        {"id":\(refreshRequest.id),"result":{"rateLimits":{"5h":{"durationSeconds":18000,"usedPercent":0},"7d":{"durationSeconds":604800,"usedPercent":2}}}}
        """))
    )

    let resetEvents = coordinator.drainViewResetEvents()
    #expect(resetEvents.count == 1)
    #expect(resetEvents[0].kind == .confirmed)
    #expect(resetEvents[0].windowKeys.sorted() == ["5h", "7d"])
  }

  // MARK: - Reset events don't change task lights

  @Test("reset detection does not alter task status lights")
  func resetDoesNotChangeTaskLights() {
    let coordinator = AppCoordinator()
    let start = Self.observationTime
    coordinator.handle(.time(.advanced(to: start)))
    coordinator.handle(.task(.monitoringConnectionEstablished(protocolCompatible: true)))
    let allRequests = coordinator.drainAppServerRequests()
    let loadedListRequest = allRequests.first { $0.method == "thread/loaded/list" }!
    let quotaRequest = allRequests.first { $0.method == "account/rateLimits/read" }!

    // Task is working
    coordinator.handle(
      .task(.appServerMessage("""
        {"id":\(loadedListRequest.id),"result":{"data":["t1"]}}
        """))
    )
    let readRequest = coordinator.drainAppServerRequests().first!
    coordinator.handle(
      .task(.appServerMessage("""
        {"id":\(readRequest.id),"result":{"thread":{"id":"t1","source":"vscode","ephemeral":false,"parentThreadId":null,"status":{"type":"active","activeFlags":[]}}}}
        """))
    )
    #expect(coordinator.viewState.status == .working)

    // Quota snapshot with reset
    coordinator.handle(
      .task(.appServerMessage("""
        {"id":\(quotaRequest.id),"result":{"rateLimits":{"5h":{"durationSeconds":18000,"usedPercent":80}}}}
        """))
    )
    coordinator.handle(.task(.quotaSnapshotRequested))
    let refreshRequest = coordinator.drainAppServerRequests().first!
    coordinator.handle(
      .task(.appServerMessage("""
        {"id":\(refreshRequest.id),"result":{"rateLimits":{"5h":{"durationSeconds":18000,"usedPercent":0}}}}
        """))
    )

    // Task status should STILL be working (unchanged)
    #expect(coordinator.viewState.status == .working)
    // But reset events should be present
    let resetEvents = coordinator.drainViewResetEvents()
    #expect(resetEvents.count == 1)
  }

  // MARK: - drainResetEvents clears after drain

  @Test("drainResetEvents clears accumulated events after draining")
  func drainResetEventsClearsAfterDrain() {
    let coordinator = AppCoordinator()
    let start = Self.observationTime
    coordinator.handle(.time(.advanced(to: start)))
    coordinator.handle(.task(.monitoringConnectionEstablished(protocolCompatible: true)))
    let initialRequest = coordinator.drainAppServerRequests().last!

    coordinator.handle(
      .task(.appServerMessage("""
        {"id":\(initialRequest.id),"result":{"rateLimits":{"5h":{"durationSeconds":18000,"usedPercent":80}}}}
        """))
    )
    coordinator.handle(.task(.quotaSnapshotRequested))
    let refreshRequest = coordinator.drainAppServerRequests().first!
    coordinator.handle(
      .task(.appServerMessage("""
        {"id":\(refreshRequest.id),"result":{"rateLimits":{"5h":{"durationSeconds":18000,"usedPercent":0}}}}
        """))
    )

    let firstDrain = coordinator.drainViewResetEvents()
    #expect(firstDrain.count == 1)

    let secondDrain = coordinator.drainViewResetEvents()
    #expect(secondDrain.isEmpty)
  }
}
