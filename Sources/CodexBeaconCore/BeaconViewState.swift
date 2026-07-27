import Foundation

public enum BeaconSize: Equatable, Sendable {
  case standard

  public var dimensions: BeaconDimensions {
    dimensions(for: .vertical)
  }

  public func dimensions(for orientation: BeaconOrientation) -> BeaconDimensions {
    switch self {
    case .standard:
      switch orientation {
      case .vertical:
        BeaconDimensions(width: 62, height: 229)
      case .horizontal:
        BeaconDimensions(width: 229, height: 62)
      }
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
  case working
  case waitingForYou
  case completed
  case monitoringUnavailable
}

public struct WaitingTask: Equatable, Sendable {
  public let threadID: String
  public let firstObservedAt: Date

  public init(threadID: String, firstObservedAt: Date) {
    self.threadID = threadID
    self.firstObservedAt = firstObservedAt
  }
}

public enum BeaconShape: Equatable, Sendable {
  case roundedRectangle(cornerRadius: Double)
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
  case steady
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
  case gauge
  case dashed
}

public struct QuotaTrackState: Equatable, Sendable {
  public let style: QuotaTrackStyle
  public let fillFraction: Double
  public let detailWindows: [QuotaWindow]

  public init(
    style: QuotaTrackStyle = .neutral,
    fillFraction: Double = 0,
    detailWindows: [QuotaWindow] = []
  ) {
    self.style = style
    self.fillFraction = fillFraction
    self.detailWindows = detailWindows
  }
}

public struct BeaconViewState: Equatable, Sendable {
  public var isVisible: Bool
  public let size: BeaconSize
  public var orientation: BeaconOrientation
  public let surface: BeaconSurfaceState
  public private(set) var lights: [BeaconLightState]
  public var quotaTrack: QuotaTrackState
  public var status: BeaconStatus
  public var lastUpdatedAt: Date?
  public var reducesMotion: Bool
  public private(set) var waitingTasks: [WaitingTask]
  public private(set) var unconfirmedCompletionTaskIDs: Set<String>

  public var dimensions: BeaconDimensions {
    size.dimensions(for: orientation)
  }

  public init(
    isVisible: Bool,
    size: BeaconSize,
    orientation: BeaconOrientation = .vertical,
    surface: BeaconSurfaceState,
    lights: [BeaconLightState],
    quotaTrack: QuotaTrackState,
    status: BeaconStatus = .idle,
    lastUpdatedAt: Date? = nil,
    reducesMotion: Bool = false,
    waitingTasks: [WaitingTask] = [],
    unconfirmedCompletionTaskIDs: Set<String> = []
  ) {
    self.isVisible = isVisible
    self.size = size
    self.orientation = orientation
    self.surface = surface
    self.lights = lights
    self.quotaTrack = quotaTrack
    self.status = status
    self.lastUpdatedAt = lastUpdatedAt
    self.reducesMotion = reducesMotion
    self.waitingTasks = waitingTasks
    self.unconfirmedCompletionTaskIDs = unconfirmedCompletionTaskIDs
  }

  public static let idle = BeaconViewState(
    isVisible: true,
    size: .standard,
    surface: .init(shape: .roundedRectangle(cornerRadius: 30), tone: .nearBlack),
    lights: [
      .init(color: .red, illumination: .off, showsRecess: true),
      .init(color: .amber, illumination: .off, showsRecess: true),
      .init(color: .green, illumination: .off, showsRecess: true),
    ],
    quotaTrack: .init(style: .neutral)
  )

  mutating func present(
    _ status: BeaconStatus,
    waitingTasks: [WaitingTask] = [],
    unconfirmedCompletionTaskIDs: Set<String> = []
  ) {
    self.status = status
    self.waitingTasks = waitingTasks
    self.unconfirmedCompletionTaskIDs = unconfirmedCompletionTaskIDs
    lights = Self.lights(for: status)
  }

  private static func lights(for status: BeaconStatus) -> [BeaconLightState] {
    let redIllumination: BeaconLightIllumination =
      status == .monitoringUnavailable ? .steady : .off
    let amberIllumination: BeaconLightIllumination =
      status == .working ? .steady : .off
    let greenIllumination: BeaconLightIllumination =
      status == .waitingForYou || status == .completed ? .steady : .off

    return [
      .init(color: .red, illumination: redIllumination, showsRecess: true),
      .init(color: .amber, illumination: amberIllumination, showsRecess: true),
      .init(color: .green, illumination: greenIllumination, showsRecess: true),
    ]
  }
}
