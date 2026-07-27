import AppKit
import Testing

@testable import CodexBeacon
@testable import CodexBeaconCore

@MainActor
struct BeaconSettingsScenarioTests {
  @Test("settings size selection updates the actual Beacon panel and its global hotkey still toggles visibility")
  func settingsSelectionUpdatesPanelAndHotKeyBehavior() {
    _ = NSApplication.shared
    let coordinator = AppCoordinator()
    let display = BeaconDisplay(
      identifier: "built-in",
      safeFrame: .init(x: 0, y: 24, width: 1_440, height: 876)
    )
    let panel = BeaconPanel(
      state: coordinator.viewState,
      onActivate: {},
      onDragEnded: {}
    )
    defer { panel.close() }

    coordinator.handle(
      .system(.displayLayoutChanged(.init(primaryDisplayIdentifier: "built-in", displays: [display])))
    )
    _ = coordinator.drainEffects()

    var registeredHotKey: BeaconHotKey?
    var registeredHandler: (() -> Void)?
    let customHotKey = BeaconHotKey(keyCode: 12, modifiers: 4_352)
    let settings = BeaconSettingsModel(
      size: .standard,
      hotKey: .init(keyCode: 8, modifiers: 6_400),
      registrationError: nil,
      onSizeSelected: { coordinator.handle(.user(.beaconSizeSelected($0))) },
      onHotKeySelected: { hotKey in
        registeredHotKey = hotKey
        registeredHandler = { coordinator.handle(.system(.globalHotKeyPressed)) }
        return nil
      }
    )

    settings.selectSize(.compact)
    guard case .placeBeacon(let placement) = coordinator.drainEffects().only else {
      Issue.record("Selecting a size must place the Beacon")
      return
    }
    panel.update(state: coordinator.viewState)
    panel.apply(placement)

    #expect(panel.frame.size == NSSize(width: 24, height: 88))

    #expect(settings.recordHotKey(customHotKey) == nil)
    #expect(registeredHotKey == customHotKey)
    registeredHandler?()
    #expect(coordinator.drainEffects() == [.hideBeacon])
  }
}

private extension Array {
  var only: Element? {
    count == 1 ? first : nil
  }
}
