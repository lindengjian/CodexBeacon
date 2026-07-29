import Foundation

public enum BeaconAppearance: String, CaseIterable, Codable, Equatable, Sendable {
  case system
  case light
  case dark

  public func resolved(for systemScheme: BeaconAppearanceScheme) -> BeaconAppearanceScheme {
    switch self {
    case .system: systemScheme
    case .light: .light
    case .dark: .dark
    }
  }
}

public enum BeaconAppearanceScheme: Equatable, Sendable {
  case light
  case dark
}
