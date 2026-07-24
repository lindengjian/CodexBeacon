import Foundation
import Testing

@testable import CodexBeaconCore

@MainActor
struct CoordinatorEventScenarioTests {
  @Test("task, time, and system events are injectable at the application seam")
  func applicationEventsUpdatePublicStateAndEffects() {
    let coordinator = AppCoordinator()
    let observationTime = Date(timeIntervalSince1970: 1_753_344_000)

    coordinator.start()
    _ = coordinator.drainEffects()
    coordinator.handle(.task(.noActiveTasksObserved))
    coordinator.handle(.time(.advanced(to: observationTime)))
    coordinator.handle(.system(.reduceMotionChanged(true)))
    coordinator.handle(.system(.visibilityChanged(false)))

    #expect(coordinator.viewState.status == .idle)
    #expect(coordinator.viewState.lastUpdatedAt == observationTime)
    #expect(coordinator.viewState.reducesMotion)
    #expect(!coordinator.viewState.isVisible)
    #expect(coordinator.drainEffects() == [.hideBeacon])
  }
}
