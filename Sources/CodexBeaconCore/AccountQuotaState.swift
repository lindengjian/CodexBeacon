import Foundation

public struct QuotaWindow: Equatable, Sendable {
  public let windowKey: String
  public let durationSeconds: TimeInterval
  public let usedPercentage: Double
  public let resetAt: Date?

  public init(
    windowKey: String,
    durationSeconds: TimeInterval,
    usedPercentage: Double,
    resetAt: Date?
  ) {
    self.windowKey = windowKey
    self.durationSeconds = durationSeconds
    self.usedPercentage = usedPercentage
    self.resetAt = resetAt
  }

  public var remainingPercentage: Double {
    max(0, min(100, 100 - usedPercentage))
  }
}

public struct AccountQuotaState: Equatable, Sendable {
  public let windows: [QuotaWindow]
  public let selectedWindow: QuotaWindow?
  public let isAvailable: Bool

  public init(
    windows: [QuotaWindow],
    selectedWindow: QuotaWindow?,
    isAvailable: Bool
  ) {
    self.windows = windows
    self.selectedWindow = selectedWindow
    self.isAvailable = isAvailable
  }

  public var remainingPercentage: Double {
    selectedWindow?.remainingPercentage ?? 0
  }
}
