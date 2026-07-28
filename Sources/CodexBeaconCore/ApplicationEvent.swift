import Foundation

public struct QuotaResetEvent: Equatable, Sendable {
  public enum Kind: Equatable, Sendable {
    /// Beacon's own rate-limits read returned a clear success or idempotent
    /// already-redeemed result confirming the reset.
    case confirmed
    /// A rate-limits notification from another client showed consistent
    /// evidence — window consumption dropped AND the reset boundary moved
    /// forward — sufficient to infer a reset.
    case inferred
  }

  public let kind: Kind
  /// Window keys whose used percentage dropped to (near) zero.
  public let windowKeys: [String]
  public let detectedAt: Date

  public init(kind: Kind, windowKeys: [String], detectedAt: Date) {
    self.kind = kind
    self.windowKeys = windowKeys
    self.detectedAt = detectedAt
  }
}

public enum TaskEvent: Equatable, Sendable {
  case monitoringConnectionEstablished(protocolCompatible: Bool)
  case monitoringRuntimeValidated
  case monitoringConnectionFailed
  case monitoringObservationBecameStale
  case monitoringSnapshotRequested
  case quotaSnapshotRequested
  case appServerMessage(String)
}

public enum TimeEvent: Equatable, Sendable {
  case advanced(to: Date)
}

public enum SystemEnvironmentEvent: Equatable, Sendable {
  case reduceMotionChanged(Bool)
  case visibilityChanged(Bool)
  case globalHotKeyPressed
  case displayLayoutChanged(BeaconDisplayLayout)
}

public enum UserEvent: Equatable, Sendable {
  case beaconActivated
  case beaconDragEnded(displayIdentifier: String, frame: BeaconRect)
  case beaconSizeSelected(BeaconSize)
}

public enum ApplicationEvent: Equatable, Sendable {
  case task(TaskEvent)
  case time(TimeEvent)
  case system(SystemEnvironmentEvent)
  case user(UserEvent)
}
