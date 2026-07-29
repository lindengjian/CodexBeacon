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

  @Test("appearance choice persists as the user's original selection")
  func appearanceChoicePersists() throws {
    let suiteName = "BeaconPreferencesTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = BeaconPreferencesStore(defaults: defaults)
    let hotKey = BeaconHotKey(keyCode: 8, modifiers: 6_400)
    let expected = BeaconPreferences(
      size: .standard,
      hotKey: hotKey,
      anchor: nil,
      appearance: .dark
    )

    store.save(expected)

    #expect(store.load(fallbackHotKey: hotKey).appearance == .dark)
  }

  @Test("legacy preferences default to following the system appearance")
  func legacyPreferencesDefaultToSystemAppearance() throws {
    let suiteName = "BeaconPreferencesTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let data = try #require(
      """
      {"size":"standard","hotKey":{"keyCode":8,"modifiers":6400},"anchor":null}
      """.data(using: .utf8)
    )
    defaults.set(data, forKey: "beaconPreferences")

    let restored = BeaconPreferencesStore(defaults: defaults).load(
      fallbackHotKey: .init(keyCode: 8, modifiers: 6_400)
    )

    #expect(restored.appearance == .system)
  }

  @Test("following the system resolves against the current system scheme")
  func systemAppearanceResolvesAgainstSystemScheme() {
    #expect(BeaconAppearance.system.resolved(for: .light) == .light)
    #expect(BeaconAppearance.system.resolved(for: .dark) == .dark)
    #expect(BeaconAppearance.light.resolved(for: .dark) == .light)
    #expect(BeaconAppearance.dark.resolved(for: .light) == .dark)
  }

  @Test("event sound defaults keep waiting and completion off while reset is on")
  func eventSoundDefaults() {
    let preferences = BeaconPreferences(
      size: .standard,
      hotKey: .init(keyCode: 8, modifiers: 6_400),
      anchor: nil
    )

    #expect(!preferences.soundPreferences[.waiting].isEnabled)
    #expect(!preferences.soundPreferences[.completion].isEnabled)
    #expect(preferences.soundPreferences[.quotaReset].isEnabled)
  }

  @Test("event sound choices persist independently across relaunch")
  func eventSoundChoicesPersistIndependently() throws {
    let suiteName = "BeaconPreferencesTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = BeaconPreferencesStore(defaults: defaults)
    let fallbackHotKey = BeaconHotKey(keyCode: 8, modifiers: 6_400)
    var preferences = BeaconPreferences(size: .standard, hotKey: fallbackHotKey, anchor: nil)
    preferences.soundPreferences[.waiting] = .init(isEnabled: true, soundName: "Basso")
    preferences.soundPreferences[.completion] = .init(isEnabled: true, soundName: "Hero")
    preferences.soundPreferences[.quotaReset] = .init(isEnabled: false, soundName: "Ping")

    store.save(preferences)
    let restored = store.load(fallbackHotKey: fallbackHotKey)

    #expect(restored.soundPreferences == preferences.soundPreferences)
  }

  @Test("legacy preferences use the event sound defaults")
  func legacyPreferencesUseEventSoundDefaults() throws {
    let suiteName = "BeaconPreferencesTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let data = try #require(
      """
      {"size":"standard","hotKey":{"keyCode":8,"modifiers":6400},"anchor":null}
      """.data(using: .utf8)
    )
    defaults.set(data, forKey: "beaconPreferences")

    let restored = BeaconPreferencesStore(defaults: defaults).load(
      fallbackHotKey: .init(keyCode: 8, modifiers: 6_400)
    )

    #expect(!restored.soundPreferences[.waiting].isEnabled)
    #expect(!restored.soundPreferences[.completion].isEnabled)
    #expect(restored.soundPreferences[.quotaReset].isEnabled)
  }
}
