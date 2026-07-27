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

  @Test("initial setup and launch-at-login choices persist without losing existing Beacon preferences")
  func setupPreferencesPersistAlongsideBeaconPreferences() throws {
    let suiteName = "BeaconPreferencesTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = BeaconPreferencesStore(defaults: defaults)
    let fallbackHotKey = BeaconHotKey(keyCode: 8, modifiers: 6_400)
    let expected = BeaconPreferences(
      size: .compact,
      hotKey: fallbackHotKey,
      anchor: .init(displayIdentifier: "built-in", edge: .right, alongEdgeOffset: 0.4),
      hasCompletedInitialSetup: true,
      launchesAtLogin: false
    )

    store.save(expected)

    #expect(store.load(fallbackHotKey: fallbackHotKey) == expected)
  }

  @Test("saved preferences from before onboarding retain their Beacon choices and use setup defaults")
  func legacyPreferencesUseInitialSetupDefaults() throws {
    let suiteName = "BeaconPreferencesTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let fallbackHotKey = BeaconHotKey(keyCode: 8, modifiers: 6_400)
    let data = try #require(
      """
      {"size":"compact","hotKey":{"keyCode":8,"modifiers":6400},"anchor":null}
      """.data(using: .utf8)
    )
    defaults.set(data, forKey: "beaconPreferences")

    let restored = BeaconPreferencesStore(defaults: defaults).load(fallbackHotKey: fallbackHotKey)

    #expect(restored.size == .compact)
    #expect(restored.hotKey == fallbackHotKey)
    #expect(!restored.hasCompletedInitialSetup)
    #expect(restored.launchesAtLogin)
    #expect(!restored.showTaskTitles)
  }

  @Test("showTaskTitles defaults to false for legacy preferences without the field")
  func showTaskTitlesDefaultsFalseForLegacyData() throws {
    let suiteName = "BeaconPreferencesTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let fallbackHotKey = BeaconHotKey(keyCode: 8, modifiers: 6_400)
    let data = try #require(
      """
      {"size":"standard","hotKey":{"keyCode":8,"modifiers":6400},"anchor":null,"hasCompletedInitialSetup":true,"launchesAtLogin":true}
      """.data(using: .utf8)
    )
    defaults.set(data, forKey: "beaconPreferences")

    let restored = BeaconPreferencesStore(defaults: defaults).load(fallbackHotKey: fallbackHotKey)

    #expect(!restored.showTaskTitles)
  }

  @Test("showTaskTitles persists and restores correctly")
  func showTaskTitlesPersists() throws {
    let suiteName = "BeaconPreferencesTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = BeaconPreferencesStore(defaults: defaults)
    let fallbackHotKey = BeaconHotKey(keyCode: 8, modifiers: 6_400)
    var preferences = BeaconPreferences(
      size: .standard,
      hotKey: fallbackHotKey,
      anchor: nil,
      showTaskTitles: true
    )

    store.save(preferences)
    let restored = store.load(fallbackHotKey: fallbackHotKey)

    #expect(restored.showTaskTitles)

    preferences.showTaskTitles = false
    store.save(preferences)
    let restoredAgain = store.load(fallbackHotKey: fallbackHotKey)

    #expect(!restoredAgain.showTaskTitles)
  }
}
