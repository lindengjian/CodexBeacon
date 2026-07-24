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

public enum MacActivationPolicy: Equatable, Sendable {
  case accessory
}

public enum BeaconWindowLevel: Equatable, Sendable {
  case floating
}

public struct BeaconWindowPresentation: Equatable, Sendable {
  public let isNonActivating: Bool
  public let level: BeaconWindowLevel
  public let appearsOnAllSpaces: Bool
  public let appearsOverFullScreenApplications: Bool

  public init(
    isNonActivating: Bool,
    level: BeaconWindowLevel,
    appearsOnAllSpaces: Bool,
    appearsOverFullScreenApplications: Bool
  ) {
    self.isNonActivating = isNonActivating
    self.level = level
    self.appearsOnAllSpaces = appearsOnAllSpaces
    self.appearsOverFullScreenApplications = appearsOverFullScreenApplications
  }
}

public struct MacApplicationPresentation: Equatable, Sendable {
  public let activationPolicy: MacActivationPolicy
  public let createsDockIcon: Bool
  public let createsMenuBarItem: Bool
  public let window: BeaconWindowPresentation

  public init(
    activationPolicy: MacActivationPolicy,
    createsDockIcon: Bool,
    createsMenuBarItem: Bool,
    window: BeaconWindowPresentation
  ) {
    self.activationPolicy = activationPolicy
    self.createsDockIcon = createsDockIcon
    self.createsMenuBarItem = createsMenuBarItem
    self.window = window
  }

  public static let beacon = MacApplicationPresentation(
    activationPolicy: .accessory,
    createsDockIcon: false,
    createsMenuBarItem: false,
    window: .init(
      isNonActivating: true,
      level: .floating,
      appearsOnAllSpaces: true,
      appearsOverFullScreenApplications: true
    )
  )
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
  public let remainingFraction: Double?

  public init(style: QuotaTrackStyle, remainingFraction: Double?) {
    self.style = style
    self.remainingFraction = remainingFraction
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
    quotaTrack: .init(style: .neutral, remainingFraction: nil)
  )
}

public enum BeaconEffect: Equatable, Sendable {
  case showBeacon
  case hideBeacon
}

public enum TaskActivity: Equatable, Sendable {
  case active
  case waitingForUser
  case completed
}

public enum TaskEvent: Equatable, Sendable {
  case snapshot([TaskActivity])
}

public enum TimeEvent: Equatable, Sendable {
  case advanced(to: Date)
}

public enum SystemEnvironmentEvent: Equatable, Sendable {
  case reduceMotionChanged(Bool)
  case visibilityChanged(Bool)
}

public enum ApplicationEvent: Equatable, Sendable {
  case task(TaskEvent)
  case time(TimeEvent)
  case system(SystemEnvironmentEvent)
}

@MainActor
public final class AppCoordinator {
  public private(set) var viewState = BeaconViewState.idle

  private var effects: [BeaconEffect] = []
  private var hasStarted = false

  public init() {}

  public func start() {
    guard !hasStarted else {
      return
    }

    hasStarted = true
    effects.append(.showBeacon)
  }

  public func handle(_ event: ApplicationEvent) {
    switch event {
    case .task(.snapshot):
      viewState.status = .idle
    case .time(.advanced(let date)):
      viewState.lastUpdatedAt = date
    case .system(.reduceMotionChanged(let reducesMotion)):
      viewState.reducesMotion = reducesMotion
    case .system(.visibilityChanged(let isVisible)):
      guard viewState.isVisible != isVisible else {
        return
      }

      viewState.isVisible = isVisible
      effects.append(isVisible ? .showBeacon : .hideBeacon)
    }
  }

  public func drainEffects() -> [BeaconEffect] {
    defer { effects.removeAll() }
    return effects
  }
}
