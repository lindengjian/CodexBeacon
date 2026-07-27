import Foundation
import Testing

@testable import CodexBeaconCore

struct BeaconPreferencesTests {
  @Test("saved size, hotkey, and anchor restore together after relaunch")
  func preferencesRestoreAfterRelaunch() {
    let suiteName = "BeaconPreferencesTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let fallbackHotKey = BeaconHotKey(keyCode: 8, modifiers: 6_400)
    let expected = BeaconPreferences(
      size: .compact,
      hotKey: .init(keyCode: 12, modifiers: 4_352),
      anchor: .init(displayIdentifier: "external", edge: .bottom, alongEdgeOffset: 72)
    )

    BeaconPreferencesStore(defaults: defaults).save(expected)

    #expect(
      BeaconPreferencesStore(defaults: defaults).load(fallbackHotKey: fallbackHotKey) == expected
    )
  }

  @Test("legacy placement restores when settings are introduced")
  func legacyPlacementMigratesToPreferences() throws {
    let suiteName = "BeaconPreferencesTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let anchor = BeaconAnchor(
      displayIdentifier: "built-in",
      edge: .right,
      alongEdgeOffset: 120
    )
    defaults.set(try JSONEncoder().encode(anchor), forKey: "beaconPlacementAnchor")

    let restored = BeaconPreferencesStore(defaults: defaults).load(
      fallbackHotKey: .init(keyCode: 8, modifiers: 6_400)
    )

    #expect(restored.size == .standard)
    #expect(restored.anchor == anchor)
  }
}
