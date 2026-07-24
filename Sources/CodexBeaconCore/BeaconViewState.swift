import Foundation

public enum BeaconSize: Equatable, Sendable {
  case standard

  public var dimensions: BeaconDimensions {
    switch self {
    case .standard:
      BeaconDimensions(width: 62, height: 229)
    }
  }
}

public struct BeaconDimensions: Equatable, Sendable {
  public let width: Double
  public let height: Double

  public init(width: Double, height: Double) {
    self.width = width
    self.height = height
  }
}

public enum BeaconStatus: Equatable, Sendable {
  case idle
}

public enum BeaconShape: Equatable, Sendable {
  case capsule
}

public enum BeaconTone: Equatable, Sendable {
  case nearBlack
}

public struct BeaconSurfaceState: Equatable, Sendable {
  public let shape: BeaconShape
  public let tone: BeaconTone

  public init(shape: BeaconShape, tone: BeaconTone) {
    self.shape = shape
    self.tone = tone
  }
}

public enum BeaconLightColor: Equatable, Sendable {
  case red
  case amber
  case green
}

public enum BeaconLightIllumination: Equatable, Sendable {
  case off
}

public struct BeaconLightState: Equatable, Sendable {
  public let color: BeaconLightColor
  public let illumination: BeaconLightIllumination
  public let showsRecess: Bool

  public init(
    color: BeaconLightColor,
    illumination: BeaconLightIllumination,
    showsRecess: Bool
  ) {
    self.color = color
    self.illumination = illumination
    self.showsRecess = showsRecess
  }
}

public enum QuotaTrackStyle: Equatable, Sendable {
  case neutral
}

public struct QuotaTrackState: Equatable, Sendable {
  public let style: QuotaTrackStyle

  public init(style: QuotaTrackStyle) {
    self.style = style
  }
}

public struct BeaconViewState: Equatable, Sendable {
  public var isVisible: Bool
  public let size: BeaconSize
  public let surface: BeaconSurfaceState
  public let lights: [BeaconLightState]
  public let quotaTrack: QuotaTrackState
  public var status: BeaconStatus
  public var lastUpdatedAt: Date?
  public var reducesMotion: Bool

  public init(
    isVisible: Bool,
    size: BeaconSize,
    surface: BeaconSurfaceState,
    lights: [BeaconLightState],
    quotaTrack: QuotaTrackState,
    status: BeaconStatus = .idle,
    lastUpdatedAt: Date? = nil,
    reducesMotion: Bool = false
  ) {
    self.isVisible = isVisible
    self.size = size
    self.surface = surface
    self.lights = lights
    self.quotaTrack = quotaTrack
    self.status = status
    self.lastUpdatedAt = lastUpdatedAt
    self.reducesMotion = reducesMotion
  }

  public static let idle = BeaconViewState(
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
}
