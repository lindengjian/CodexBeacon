import CryptoKit
import Foundation

/// The minimum quota information retained between Beacon runs. The account
/// context is stored only as a SHA-256 digest so an account identifier is
/// never written to local preferences in clear text.
public struct QuotaResetBaseline: Codable, Equatable, Sendable {
  public let accountContextDigest: String?
  public let windowKey: String
  public let durationSeconds: TimeInterval
  public let usedPercentage: Double
  public let resetAt: Date?
  public let observedAt: Date

  init(
    accountContextDigest: String?,
    window: QuotaWindow,
    observedAt: Date
  ) {
    self.accountContextDigest = accountContextDigest
    windowKey = window.windowKey
    durationSeconds = window.durationSeconds
    usedPercentage = window.usedPercentage
    resetAt = window.resetAt
    self.observedAt = observedAt
  }
}

/// Persists only the latest quota baseline needed to make a conservative
/// restart notification decision. It intentionally contains no task data or raw
/// account/authentication content.
public final class QuotaResetBaselineStore: @unchecked Sendable {
  private let defaults: UserDefaults
  private let key: String

  public init(
    defaults: UserDefaults = .standard,
    key: String = "quotaResetBaseline"
  ) {
    self.defaults = defaults
    self.key = key
  }

  public func load() -> QuotaResetBaseline? {
    guard let data = defaults.data(forKey: key) else {
      return nil
    }
    return try? JSONDecoder().decode(QuotaResetBaseline.self, from: data)
  }

  func replace(with observation: QuotaBaselineObservation) {
    let baseline = QuotaResetBaseline(
      accountContextDigest: observation.accountContextID.map(Self.digest),
      window: observation.window,
      observedAt: observation.observedAt
    )
    guard let data = try? JSONEncoder().encode(baseline) else {
      return
    }
    defaults.set(data, forKey: key)
  }

  func clear() {
    defaults.removeObject(forKey: key)
  }

  static func digest(_ identifier: String) -> String {
    SHA256.hash(data: Data(identifier.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}

/// A snapshot suitable for comparing a persistent baseline. These are emitted
/// only for responses to Beacon's own `account/rateLimits/read` requests.
struct QuotaBaselineObservation {
  let accountContextID: String?
  let window: QuotaWindow
  let observedAt: Date
  let isInitialSnapshotForConnection: Bool
}

enum QuotaResetEvidencePolicy {
  static let resetThreshold: Double = 5
  static let meaningfulUsageThreshold: Double = 10
}

struct ConfirmableQuotaResetDetector {
  private let store: QuotaResetBaselineStore

  private static let maximumBaselineAge: TimeInterval = 24 * 60 * 60

  init(store: QuotaResetBaselineStore) {
    self.store = store
  }

  /// Returns at most one reset event. Missing account identity is deliberately
  /// a no-notification path: a percentage change must never bridge accounts.
  func observe(_ observation: QuotaBaselineObservation) -> QuotaResetEvent? {
    let previous = store.load()

    guard let accountContextID = observation.accountContextID else {
      // The account read can legitimately arrive after the quota response.
      // Preserve a prior identified baseline until that response gives us a
      // safe context to compare, rather than discarding valid evidence.
      if !observation.isInitialSnapshotForConnection {
        store.replace(with: observation)
      }
      return nil
    }

    let currentDigest = QuotaResetBaselineStore.digest(accountContextID)
    if let previousDigest = previous?.accountContextDigest,
      previousDigest != currentDigest
    {
      // Account/authentication context is observable and changed. Remove the
      // old baseline before saving the new one so it cannot bridge accounts.
      store.clear()
      store.replace(with: observation)
      return nil
    }

    guard observation.isInitialSnapshotForConnection,
      let previous,
      let previousDigest = previous.accountContextDigest,
      let currentResetAt = observation.window.resetAt,
      let previousResetAt = previous.resetAt,
      observation.window.durationSeconds > 0
    else {
      store.replace(with: observation)
      return nil
    }

    defer { store.replace(with: observation) }
    let baselineAge = observation.observedAt.timeIntervalSince(previous.observedAt)
    guard baselineAge >= 0, baselineAge <= Self.maximumBaselineAge,
      previousDigest == currentDigest,
      previous.windowKey == observation.window.windowKey,
      previous.durationSeconds == observation.window.durationSeconds,
      previous.usedPercentage >= QuotaResetEvidencePolicy.meaningfulUsageThreshold,
      observation.window.usedPercentage <= QuotaResetEvidencePolicy.resetThreshold,
      currentResetAt > previousResetAt
    else {
      return nil
    }

    // `resetsAt` is the end of the current window; deriving its start keeps
    // the report tied to a reset that is itself recent, not merely a recent
    // observation of an old, empty window.
    let resetOccurredAt = currentResetAt.addingTimeInterval(-observation.window.durationSeconds)
    guard resetOccurredAt >= previous.observedAt,
      resetOccurredAt <= observation.observedAt,
      observation.observedAt.timeIntervalSince(resetOccurredAt) <= Self.maximumBaselineAge
    else {
      return nil
    }

    return QuotaResetEvent(
      kind: .confirmed,
      windowKeys: [observation.window.windowKey],
      detectedAt: observation.observedAt
    )
  }

  func clearBaseline() {
    store.clear()
  }

  func clearBaselineIfAccountChanged(to identifier: String) {
    guard let previousDigest = store.load()?.accountContextDigest,
      previousDigest != QuotaResetBaselineStore.digest(identifier)
    else {
      return
    }
    store.clear()
  }
}
