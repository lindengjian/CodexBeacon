import Testing

@testable import CodexBeaconCore

@MainActor
struct IdleBeaconScenarioTests {
  @Test("application launch presents the user-visible idle Beacon")
  func applicationLaunchPresentsIdleBeacon() {
    let coordinator = AppCoordinator()

    coordinator.start()

    #expect(
      coordinator.viewState
        == BeaconViewState(
          isVisible: true,
          size: .standard,
          surface: .init(shape: .capsule, tone: .nearBlack),
          lights: [
            .init(color: .red, illumination: .off, showsRecess: true),
            .init(color: .amber, illumination: .off, showsRecess: true),
            .init(color: .green, illumination: .off, showsRecess: true),
          ],
          quotaTrack: .init(style: .neutral)
        )
    )
    #expect(coordinator.drainEffects() == [.showBeacon])
  }
}
