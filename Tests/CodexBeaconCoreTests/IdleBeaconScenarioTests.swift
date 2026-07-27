import Testing

@testable import CodexBeaconCore

@MainActor
struct IdleBeaconScenarioTests {
  @Test("application launch without monitoring evidence fails closed")
  func applicationLaunchPresentsMonitoringUnavailableBeacon() {
    let coordinator = AppCoordinator()

    coordinator.start()

    #expect(coordinator.viewState.isVisible == true)
    #expect(coordinator.viewState.size == .standard)
    #expect(coordinator.viewState.status == .monitoringUnavailable)
    #expect(coordinator.viewState.lights == [
      .init(color: .red, illumination: .steady, showsRecess: true),
      .init(color: .amber, illumination: .off, showsRecess: true),
      .init(color: .green, illumination: .off, showsRecess: true),
    ])
    #expect(coordinator.viewState.quotaTrack == .init(style: .neutral))
    #expect(coordinator.drainEffects() == [.showBeacon])
  }
}
