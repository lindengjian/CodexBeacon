import Foundation

/// Bounds reconnect attempts after a passive monitoring connection fails.
/// A successful connection restores a prompt retry if the transport later drops.
public struct MonitoringReconnectBackoff: Sendable {
  private static let delays: [TimeInterval] = [2, 5, 15, 30]
  private var failureCount = 0

  public init() {}

  public mutating func nextDelayAfterFailure() -> TimeInterval {
    let index = min(failureCount, Self.delays.count - 1)
    failureCount += 1
    return Self.delays[index]
  }

  public mutating func recordSuccessfulConnection() {
    failureCount = 0
  }
}
