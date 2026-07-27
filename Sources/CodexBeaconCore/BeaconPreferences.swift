import Foundation

public struct BeaconHotKey: Codable, Equatable, Sendable {
  public let keyCode: UInt32
  public let modifiers: UInt32

  public init(keyCode: UInt32, modifiers: UInt32) {
    self.keyCode = keyCode
    self.modifiers = modifiers
  }
}

public struct BeaconPreferences: Codable, Equatable, Sendable {
  public var size: BeaconSize
  public var hotKey: BeaconHotKey
  public var anchor: BeaconAnchor?

  public init(size: BeaconSize, hotKey: BeaconHotKey, anchor: BeaconAnchor?) {
    self.size = size
    self.hotKey = hotKey
    self.anchor = anchor
  }
}

public struct BeaconPreferencesStore {
  private static let legacyAnchorKey = "beaconPlacementAnchor"
  private let defaults: UserDefaults
  private let key: String

  public init(defaults: UserDefaults = .standard, key: String = "beaconPreferences") {
    self.defaults = defaults
    self.key = key
  }

  public func load(fallbackHotKey: BeaconHotKey) -> BeaconPreferences {
    guard
      let data = defaults.data(forKey: key),
      let preferences = try? JSONDecoder().decode(BeaconPreferences.self, from: data)
    else {
      let legacyAnchor = defaults.data(forKey: Self.legacyAnchorKey).flatMap {
        try? JSONDecoder().decode(BeaconAnchor.self, from: $0)
      }
      return BeaconPreferences(size: .standard, hotKey: fallbackHotKey, anchor: legacyAnchor)
    }
    return preferences
  }

  public func save(_ preferences: BeaconPreferences) {
    guard let data = try? JSONEncoder().encode(preferences) else {
      return
    }
    defaults.set(data, forKey: key)
  }
}
