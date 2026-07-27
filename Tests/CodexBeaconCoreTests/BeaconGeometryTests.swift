import Testing

@testable import CodexBeaconCore

struct BeaconGeometryTests {
  @Test("standard Beacon uses the specified vertical dimensions")
  func standardBeaconDimensions() {
    #expect(BeaconSize.standard.dimensions == .init(width: 62, height: 229))
  }

  @Test("dragging to a display's top safe edge rotates and snaps Beacon horizontally")
  @MainActor
  func dragToTopSafeEdge() {
    let coordinator = AppCoordinator()
    let display = BeaconDisplay(
      identifier: "built-in",
      safeFrame: .init(x: 100, y: 80, width: 800, height: 800)
    )

    coordinator.handle(
      .system(.displayLayoutChanged(.init(primaryDisplayIdentifier: "built-in", displays: [display])))
    )
    _ = coordinator.drainEffects()
    coordinator.handle(
      .user(
        .beaconDragEnded(
          displayIdentifier: "built-in",
          frame: .init(x: 250, y: 650, width: 62, height: 229)
        )
      )
    )

    #expect(coordinator.viewState.orientation == .horizontal)
    #expect(
      coordinator.drainEffects() == [
        .placeBeacon(
          .init(
            anchor: .init(displayIdentifier: "built-in", edge: .top, alongEdgeOffset: 150),
            frame: .init(x: 250, y: 818, width: 229, height: 62)
          )
        )
      ]
    )
  }

  @Test("a disconnected display migrates to the primary display and does not reclaim Beacon on reconnect")
  @MainActor
  func disconnectedDisplayMigratesWithoutAutomaticReturn() {
    let coordinator = AppCoordinator()
    let builtIn = BeaconDisplay(
      identifier: "built-in",
      safeFrame: .init(x: 0, y: 24, width: 1_440, height: 876)
    )
    let external = BeaconDisplay(
      identifier: "external",
      safeFrame: .init(x: 1_440, y: 0, width: 1_920, height: 1_080)
    )

    coordinator.handle(
      .system(
        .displayLayoutChanged(
          .init(primaryDisplayIdentifier: "built-in", displays: [builtIn, external])
        )
      )
    )
    _ = coordinator.drainEffects()
    coordinator.handle(
      .user(
        .beaconDragEnded(
          displayIdentifier: "external",
          frame: .init(x: 3_290, y: 300, width: 62, height: 229)
        )
      )
    )
    _ = coordinator.drainEffects()

    coordinator.handle(
      .system(.displayLayoutChanged(.init(primaryDisplayIdentifier: "built-in", displays: [builtIn])))
    )

    #expect(
      coordinator.drainEffects() == [
        .placeBeacon(
          .init(
            anchor: .init(displayIdentifier: "built-in", edge: .right, alongEdgeOffset: 300),
            frame: .init(x: 1_378, y: 324, width: 62, height: 229)
          )
        )
      ]
    )

    coordinator.handle(
      .system(
        .displayLayoutChanged(
          .init(primaryDisplayIdentifier: "built-in", displays: [builtIn, external])
        )
      )
    )

    #expect(
      coordinator.drainEffects() == [
        .placeBeacon(
          .init(
            anchor: .init(displayIdentifier: "built-in", edge: .right, alongEdgeOffset: 300),
            frame: .init(x: 1_378, y: 324, width: 62, height: 229)
          )
        )
      ]
    )
  }
}
