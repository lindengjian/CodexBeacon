import Foundation

public enum QuotaRefreshSchedule {
  public static func interval(for status: BeaconStatus) -> TimeInterval {
    switch status {
    case .working:
      5
    case .idle, .waitingForYou, .completed, .monitoringUnavailable:
      30
    }
  }
}
