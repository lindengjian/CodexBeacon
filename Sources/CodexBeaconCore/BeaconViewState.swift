import Foundation

public enum BeaconSize: String, Codable, Equatable, Hashable, Sendable {
  case standard
  case compact

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
    case .compact:
      switch orientation {
      case .vertical:
        BeaconDimensions(width: 24, height: 88)
      case .horizontal:
        BeaconDimensions(width: 88, height: 24)
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
  public let title: String?

  public init(threadID: String, firstObservedAt: Date, title: String? = nil) {
    self.threadID = threadID
    self.firstObservedAt = firstObservedAt
    self.title = title
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

/// How a single Beacon lamp is illuminated.
///
/// - `off`: unlit, dim recess only.
/// - `steady`: solid, no animation. Used for red (monitoring unavailable) and
///   green (completed).
/// - `breathing`: slow opacity pulse. Used for amber (working).
/// - `flashing`: faster, more explicit opacity pulse. Used for green (waiting
///   for approval / authorization / answer).
public enum BeaconLightIllumination: Equatable, Sendable {
  case off
  case steady
  case breathing
  case flashing
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

public enum HoverTaskState: Equatable, Sendable {
  case working
  case waitingForYou
  case completed
}

public struct HoverTaskEntry: Equatable, Sendable {
  public let threadID: String
  public let title: String?
  public let sessionId: String?
  public let state: HoverTaskState

  public init(
    threadID: String,
    title: String?,
    sessionId: String? = nil,
    state: HoverTaskState
  ) {
    self.threadID = threadID
    self.title = title
    self.sessionId = sessionId
    self.state = state
  }
}

public struct HoverDetailState: Equatable, Sendable {
  public let status: BeaconStatus
  public let workingCount: Int
  public let waitingCount: Int
  public let completedCount: Int
  public let tasks: [HoverTaskEntry]
  public let quotaWindows: [QuotaWindow]
  public let lastUpdatedAt: Date?
  public let taskError: String?
  public let quotaError: String?
  public let showTaskTitles: Bool

  public init(
    status: BeaconStatus,
    workingCount: Int,
    waitingCount: Int,
    completedCount: Int,
    tasks: [HoverTaskEntry],
    quotaWindows: [QuotaWindow],
    lastUpdatedAt: Date?,
    taskError: String?,
    quotaError: String?,
    showTaskTitles: Bool
  ) {
    self.status = status
    self.workingCount = workingCount
    self.waitingCount = waitingCount
    self.completedCount = completedCount
    self.tasks = tasks
    self.quotaWindows = quotaWindows
    self.lastUpdatedAt = lastUpdatedAt
    self.taskError = taskError
    self.quotaError = quotaError
    self.showTaskTitles = showTaskTitles
  }

  public var aggregateCountsDescription: String {
    var parts: [String] = []
    if workingCount > 0 {
      parts.append("工作 \(workingCount)")
    }
    if waitingCount > 0 {
      parts.append("审批 \(waitingCount)")
    }
    if completedCount > 0 {
      parts.append("完成 \(completedCount)")
    }
    return parts.joined(separator: " · ")
  }
}

public struct BeaconViewState: Equatable, Sendable {
  public var isVisible: Bool
  public var size: BeaconSize
  public var orientation: BeaconOrientation
  public let surface: BeaconSurfaceState
  public private(set) var lights: [BeaconLightState]
  public var quotaTrack: QuotaTrackState
  public var status: BeaconStatus
  public var lastUpdatedAt: Date?
  public var reducesMotion: Bool
  public private(set) var waitingTasks: [WaitingTask]
  public private(set) var unconfirmedCompletionTaskIDs: Set<String>
  public var hoverDetail: HoverDetailState?
  public var showTaskTitles: Bool

  /// Reset events accumulated since the last drain. The app delegate drains
  /// these to trigger notifications and border pulse without altering the
  /// three task-status lights.
  public var pendingResetEvents: [QuotaResetEvent]
  /// Temporary message shown on the Beacon surface after a confirmed reset
  /// (e.g. "额度已重置 · 100%").
  public var activeResetMessage: String?
  public var activeResetMessageExpiresAt: Date?

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
    unconfirmedCompletionTaskIDs: Set<String> = [],
    hoverDetail: HoverDetailState? = nil,
    showTaskTitles: Bool = false,
    pendingResetEvents: [QuotaResetEvent] = [],
    activeResetMessage: String? = nil,
    activeResetMessageExpiresAt: Date? = nil
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
    self.hoverDetail = hoverDetail
    self.showTaskTitles = showTaskTitles
    self.pendingResetEvents = pendingResetEvents
    self.activeResetMessage = activeResetMessage
    self.activeResetMessageExpiresAt = activeResetMessageExpiresAt
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

  /// Drains and returns accumulated reset events, clearing the pending list.
  public mutating func drainResetEvents() -> [QuotaResetEvent] {
    defer { pendingResetEvents.removeAll() }
    return pendingResetEvents
  }

  /// Sets the temporary reset message that appears on the Beacon surface.
  /// The message is automatically cleared after `duration` seconds by the
  /// app delegate during the next time-advance tick.
  public mutating func setResetMessage(_ message: String, expiresAt: Date) {
    activeResetMessage = message
    activeResetMessageExpiresAt = expiresAt
  }

  /// Clears the temporary reset message if it has expired. Returns `true`
  /// when the message was cleared (so callers can update the panel).
  public mutating func clearExpiredResetMessage(now: Date) -> Bool {
    guard let expiresAt = activeResetMessageExpiresAt, now >= expiresAt else {
      return false
    }
    activeResetMessage = nil
    activeResetMessageExpiresAt = nil
    return true
  }

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
      status == .working ? .breathing : .off
    let greenIllumination: BeaconLightIllumination = {
      switch status {
      case .waitingForYou: return .flashing
      case .completed: return .steady
      default: return .off
      }
    }()

    return [
      .init(color: .red, illumination: redIllumination, showsRecess: true),
      .init(color: .amber, illumination: amberIllumination, showsRecess: true),
      .init(color: .green, illumination: greenIllumination, showsRecess: true),
    ]
  }
}
