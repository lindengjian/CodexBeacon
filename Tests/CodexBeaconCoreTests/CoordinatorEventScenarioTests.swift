import Foundation
import Testing

@testable import CodexBeaconCore

@MainActor
struct CoordinatorEventScenarioTests {
  @Test("shared runtime validation presents the loaded Desktop working task")
  func sharedRuntimeValidationPresentsLoadedWorkingTask() {
    let coordinator = AppCoordinator(requiresSharedRuntimeEvidence: true)

    coordinator.handle(.task(.monitoringConnectionEstablished(protocolCompatible: true)))
    let loadedRequest = coordinator.drainAppServerRequests().first!
    coordinator.handle(
      .task(.appServerMessage("""
        {"id":\(loadedRequest.id),"result":{"data":["desktop-thread"]}}
        """))
    )
    let readRequest = coordinator.drainAppServerRequests().first!
    coordinator.handle(
      .task(.appServerMessage("""
        {"id":\(readRequest.id),"result":{"thread":{"id":"desktop-thread","source":"vscode","ephemeral":false,"parentThreadId":null,"status":{"type":"active","activeFlags":[]}}}}
        """))
    )

    #expect(coordinator.viewState.status == .monitoringUnavailable)

    coordinator.handle(.task(.monitoringRuntimeValidated))

    #expect(coordinator.viewState.status == .working)
    #expect(coordinator.viewState.lights[1].illumination == .breathing)
  }

  @Test("monitor reconnect retries use bounded backoff and reset after recovery")
  func monitoringReconnectBackoffResetsAfterRecovery() {
    var backoff = MonitoringReconnectBackoff()

    #expect(backoff.nextDelayAfterFailure() == 2)
    #expect(backoff.nextDelayAfterFailure() == 5)
    #expect(backoff.nextDelayAfterFailure() == 15)
    #expect(backoff.nextDelayAfterFailure() == 30)
    #expect(backoff.nextDelayAfterFailure() == 30)

    backoff.recordSuccessfulConnection()

    #expect(backoff.nextDelayAfterFailure() == 2)
  }

  @Test("task, time, and system events are injectable at the application seam")
  func applicationEventsUpdatePublicStateAndEffects() {
    let coordinator = AppCoordinator()
    let observationTime = Date(timeIntervalSince1970: 1_753_344_000)

    coordinator.start()
    _ = coordinator.drainEffects()
    coordinator.handle(
      .task(.monitoringConnectionEstablished(protocolCompatible: true))
    )
    let loadedListRequest = coordinator.drainAppServerRequests().first!
    coordinator.handle(
      .task(
        .appServerMessage(
          """
          {"id":\(loadedListRequest.id),"result":{"data":[]}}
          """
        )
      )
    )
    coordinator.handle(.time(.advanced(to: observationTime)))
    coordinator.handle(.system(.reduceMotionChanged(true)))
    coordinator.handle(.system(.visibilityChanged(false)))

    #expect(coordinator.viewState.status == .idle)
    #expect(coordinator.viewState.lastUpdatedAt == observationTime)
    #expect(coordinator.viewState.reducesMotion)
    #expect(!coordinator.viewState.isVisible)
    #expect(coordinator.drainEffects() == [.hideBeacon])
  }

  @Test("shared-runtime mode stays unavailable until Desktop evidence is validated")
  func sharedRuntimeEvidenceGatesTaskPresentation() {
    let coordinator = AppCoordinator(requiresSharedRuntimeEvidence: true)

    coordinator.handle(
      .task(.monitoringConnectionEstablished(protocolCompatible: true))
    )
    let loadedListRequest = coordinator.drainAppServerRequests().first!
    coordinator.handle(
      .task(
        .appServerMessage(
          """
          {"id":\(loadedListRequest.id),"result":{"data":[]}}
          """
        )
      )
    )

    #expect(coordinator.viewState.status == .monitoringUnavailable)

    coordinator.handle(.user(.beaconActivated))

    #expect(coordinator.viewState.status == .monitoringUnavailable)

    coordinator.handle(.task(.monitoringRuntimeValidated))

    #expect(coordinator.viewState.status == .idle)
  }

  @Test("missing Desktop evidence does not erase a successfully read quota")
  func missingDesktopEvidencePreservesQuota() {
    let coordinator = AppCoordinator(requiresSharedRuntimeEvidence: true)

    coordinator.handle(
      .task(.monitoringConnectionEstablished(protocolCompatible: true))
    )
    let quotaRequest = coordinator.drainAppServerRequests().first {
      $0.method == "account/rateLimits/read"
    }!
    coordinator.handle(
      .task(.appServerMessage("""
        {"id":\(quotaRequest.id),"result":{"rateLimits":{"week":{"durationSeconds":604800,"usedPercent":1}}}}
        """))
    )

    #expect(coordinator.viewState.quotaTrack.style == .gauge)
    #expect(abs(coordinator.viewState.quotaTrack.fillFraction - 0.99) < 0.01)

    coordinator.handle(.task(.monitoringRuntimeEvidenceUnavailable))

    #expect(coordinator.viewState.status == .monitoringUnavailable)
    #expect(coordinator.viewState.quotaTrack.style == .gauge)
    #expect(abs(coordinator.viewState.quotaTrack.fillFraction - 0.99) < 0.01)
  }
}
