import Foundation

public enum TaskEvent: Equatable, Sendable {
  case monitoringConnectionEstablished(protocolCompatible: Bool)
  case monitoringRuntimeValidated
  case monitoringConnectionFailed
  case monitoringObservationBecameStale
  case appServerMessage(String)
}

public enum TimeEvent: Equatable, Sendable {
  case advanced(to: Date)
}

public enum SystemEnvironmentEvent: Equatable, Sendable {
  case reduceMotionChanged(Bool)
  case visibilityChanged(Bool)
  case displayLayoutChanged(BeaconDisplayLayout)
}

public enum UserEvent: Equatable, Sendable {
  case beaconActivated
  case beaconDragEnded(displayIdentifier: String, frame: BeaconRect)
}

public enum ApplicationEvent: Equatable, Sendable {
  case task(TaskEvent)
  case time(TimeEvent)
  case system(SystemEnvironmentEvent)
  case user(UserEvent)
}
