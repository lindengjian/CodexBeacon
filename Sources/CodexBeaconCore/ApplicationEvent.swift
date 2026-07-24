import Foundation

public enum TaskEvent: Equatable, Sendable {
  case noActiveTasksObserved
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
