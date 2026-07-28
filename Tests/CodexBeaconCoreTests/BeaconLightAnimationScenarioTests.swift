import Foundation
import Testing

@testable import CodexBeaconCore

@MainActor
struct BeaconLightAnimationScenarioTests {
  @Test("idle state keeps all three lights off")
  func idleLightsAreAllOff() {
    let coordinator = AppCoordinator()
    coordinator.start()

    coordinator.handle(
      .system(.displayLayoutChanged(.init(
        primaryDisplayIdentifier: "built-in",
        displays: [
          BeaconDisplay(
            identifier: "built-in",
            safeFrame: .init(x: 0, y: 0, width: 200, height: 200)
          ),
        ]
      )))
    )
    _ = coordinator.drainEffects()

    establishSnapshot(for: coordinator, threads: [:])

    #expect(coordinator.viewState.status == .idle)
    #expect(
      coordinator.viewState.lights == [
        .init(color: .red, illumination: .off, showsRecess: true),
        .init(color: .amber, illumination: .off, showsRecess: true),
        .init(color: .green, illumination: .off, showsRecess: true),
      ]
    )
  }

  @Test("working state breathes the amber lamp and keeps the others off")
  func workingStateBreathesAmber() {
    let coordinator = AppCoordinator()

    establishSnapshot(for: coordinator, threads: ["worker": .working])

    #expect(coordinator.viewState.status == .working)
    #expect(
      coordinator.viewState.lights == [
        .init(color: .red, illumination: .off, showsRecess: true),
        .init(color: .amber, illumination: .breathing, showsRecess: true),
        .init(color: .green, illumination: .off, showsRecess: true),
      ]
    )
  }

  @Test("waiting-for-you state flashes the green lamp and keeps the others off")
  func waitingForYouStateFlashesGreen() {
    let coordinator = AppCoordinator()

    establishSnapshot(for: coordinator, threads: ["needs-approval": .waitingOnApproval])

    #expect(coordinator.viewState.status == .waitingForYou)
    #expect(
      coordinator.viewState.lights == [
        .init(color: .red, illumination: .off, showsRecess: true),
        .init(color: .amber, illumination: .off, showsRecess: true),
        .init(color: .green, illumination: .flashing, showsRecess: true),
      ]
    )
  }

  @Test("completed state lights the green lamp steady, distinct from waiting")
  func completedStateLightsGreenSteady() {
    let coordinator = AppCoordinator()

    establishSnapshot(for: coordinator, threads: ["worker": .working])
    sendStatus(.idle, for: "worker", to: coordinator)
    for request in coordinator.drainAppServerRequests() {
      coordinator.handle(
        .task(.appServerMessage("""
          {"id":\(request.id),"result":{"data":[{"id":"turn-worker","status":"completed"}]}}
          """))
      )
    }

    #expect(coordinator.viewState.status == .completed)
    #expect(
      coordinator.viewState.lights == [
        .init(color: .red, illumination: .off, showsRecess: true),
        .init(color: .amber, illumination: .off, showsRecess: true),
        .init(color: .green, illumination: .steady, showsRecess: true),
      ]
    )
  }

  @Test("unavailable state keeps the red lamp steady, distinct from working and waiting")
  func unavailableStateLightsRedSteady() {
    let coordinator = AppCoordinator()

    coordinator.handle(.task(.monitoringConnectionFailed))

    #expect(coordinator.viewState.status == .monitoringUnavailable)
    #expect(
      coordinator.viewState.lights == [
        .init(color: .red, illumination: .steady, showsRecess: true),
        .init(color: .amber, illumination: .off, showsRecess: true),
        .init(color: .green, illumination: .off, showsRecess: true),
      ]
    )
  }

  @Test("breathing and flashing are distinct illuminations so the view layer can differentiate them")
  func breathingAndFlashingAreDistinct() {
    #expect(BeaconLightIllumination.breathing != BeaconLightIllumination.flashing)
    #expect(BeaconLightIllumination.breathing != .steady)
    #expect(BeaconLightIllumination.flashing != .steady)
  }
}
