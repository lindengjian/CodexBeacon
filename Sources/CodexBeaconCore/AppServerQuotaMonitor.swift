import Foundation

struct AppServerQuotaMonitor {
  private let requestIDGenerator: AppServerRequestIDGenerator
  private var windows: [String: QuotaWindow] = [:]
  private var state: QuotaMonitorState = .notStarted
  private var pendingSnapshotRequestID: Int?
  private var requests: [AppServerRequest] = []
  private var resetEvents: [QuotaResetEvent] = []

  /// Threshold below which a window is considered effectively reset (used % ≈ 0).
  private static let resetThreshold: Double = 5
  /// A window with used percentage at or above this value is considered
  /// meaningfully consumed before a reset.
  private static let meaningfulUsageThreshold: Double = 10

  init(requestIDGenerator: AppServerRequestIDGenerator) {
    self.requestIDGenerator = requestIDGenerator
  }

  var accountQuota: AccountQuotaState {
    guard state == .available else {
      return AccountQuotaState(windows: [], selectedWindow: nil, isAvailable: false)
    }
    let valid = windows.values.filter { $0.durationSeconds > 0 }
    let selected = valid.min { $0.durationSeconds < $1.durationSeconds }
    let all = windows.values.sorted { lhs, rhs in
      let lh = lhs.durationSeconds > 0 ? lhs.durationSeconds : TimeInterval.infinity
      let rh = rhs.durationSeconds > 0 ? rhs.durationSeconds : TimeInterval.infinity
      return lh < rh
    }
    return AccountQuotaState(
      windows: all,
      selectedWindow: selected,
      isAvailable: true
    )
  }

  var isAvailable: Bool { state == .available }

  mutating func connectionEstablished() {
    state = .waitingForSnapshot
    windows.removeAll()
    pendingSnapshotRequestID = nil
    requests.removeAll()
    resetEvents.removeAll()
    requestSnapshot()
  }

  mutating func connectionFailed() {
    state = .unavailable
    windows.removeAll()
    pendingSnapshotRequestID = nil
    requests.removeAll()
    resetEvents.removeAll()
  }

  mutating func observationBecameStale() {
    connectionFailed()
  }

  mutating func snapshotRequested() {
    guard state != .notStarted, state != .unavailable else {
      return
    }
    requestSnapshot()
  }

  /// Returns `true` when the message is a quota-related message and was handled.
  mutating func handle(message: String, observedAt: Date) -> Bool {
    guard state != .notStarted, state != .unavailable else {
      return false
    }
    guard let data = message.data(using: .utf8) else {
      return false
    }
    guard let header = try? JSONDecoder().decode(QuotaMessageHeader.self, from: data) else {
      return false
    }

    if let method = header.method {
      guard method == QuotaMethod.rateLimitsUpdated else {
        return false
      }
      return handleRateLimitsNotification(data, observedAt: observedAt)
    }

    if let requestID = header.id, requestID == pendingSnapshotRequestID {
      pendingSnapshotRequestID = nil
      let updated = handleRateLimitsSnapshot(data, observedAt: observedAt)
      if !updated, windows.isEmpty {
        state = .waitingForSnapshot
      }
      return true
    }

    return false
  }

  mutating func drainRequests() -> [AppServerRequest] {
    defer { requests.removeAll() }
    return requests
  }

  mutating func drainResetEvents() -> [QuotaResetEvent] {
    defer { resetEvents.removeAll() }
    return resetEvents
  }

  private mutating func requestSnapshot() {
    let request = AppServerRequest(
      id: requestIDGenerator.next(), method: QuotaMethod.readRateLimits)
    pendingSnapshotRequestID = request.id
    requests.append(request)
  }

  private mutating func handleRateLimitsSnapshot(_ data: Data, observedAt: Date) -> Bool {
    guard let response = try? JSONDecoder().decode(RateLimitsResponse.self, from: data) else {
      return false
    }
    let previous = windows
    windows.removeAll()
    for (key, entry) in response.result.rateLimits.windows {
      windows[key] = window(from: entry, key: key, previous: previous[key])
    }
    state = .available
    detectResets(previous: previous, observedAt: observedAt, kind: .confirmed)
    return true
  }

  private mutating func handleRateLimitsNotification(_ data: Data, observedAt: Date) -> Bool {
    guard
      let notification = try? JSONDecoder().decode(
        RateLimitsNotification.self, from: data)
    else {
      return false
    }
    let previous = windows
    windows.removeAll()
    for (key, entry) in notification.params.rateLimits {
      windows[key] = window(from: entry, key: key, previous: previous[key])
    }
    state = .available
    detectResets(previous: previous, observedAt: observedAt, kind: .inferred)
    return true
  }

  /// Detects quota resets by comparing previous window state to current.
  ///
  /// A reset is recognised when a window that previously had meaningful
  /// usage (≥ `meaningfulUsageThreshold`) now has near-zero usage
  /// (≤ `resetThreshold`).
  ///
  /// For inferred resets from other-client notifications, we additionally
  /// require that the `resetAt` boundary has moved forward, providing
  /// consistent dual evidence.
  private mutating func detectResets(
    previous: [String: QuotaWindow],
    observedAt: Date,
    kind: QuotaResetEvent.Kind
  ) {
    var resetKeys: [String] = []
    for (key, current) in windows {
      let prev = previous[key]
      let wasMeaningful = (prev?.usedPercentage ?? 0) >= Self.meaningfulUsageThreshold
      let isNearZero = current.usedPercentage <= Self.resetThreshold

      guard wasMeaningful && isNearZero else {
        continue
      }

      switch kind {
      case .confirmed:
        // Beacon's own snapshot confirmed the reset — no additional
        // evidence required beyond the usage drop.
        resetKeys.append(key)
      case .inferred:
        // For inferred resets (other-client notifications), require
        // consistent dual evidence: usage dropped AND the reset
        // boundary moved forward.
        if let prevReset = prev?.resetAt,
          let currentReset = current.resetAt,
          currentReset > prevReset
        {
          resetKeys.append(key)
        }
      }
    }

    if !resetKeys.isEmpty {
      resetEvents.append(
        QuotaResetEvent(
          kind: kind,
          windowKeys: resetKeys.sorted(),
          detectedAt: observedAt
        )
      )
    }
  }

  private func window(
    from entry: RateLimitEntry,
    key: String,
    previous: QuotaWindow?
  ) -> QuotaWindow {
    let resetAt = entry.resetAt.flatMap {
      ISO8601DateFormatter().date(from: $0)
    } ?? entry.resetsAt.map(Date.init(timeIntervalSince1970:)) ?? previous?.resetAt
    return QuotaWindow(
      windowKey: key,
      durationSeconds: entry.durationSeconds
        ?? entry.windowDurationMins.map { $0 * 60 }
        ?? previous?.durationSeconds
        ?? 0,
      usedPercentage: entry.usedPercent ?? previous?.usedPercentage ?? 0,
      resetAt: resetAt
    )
  }
}

private enum QuotaMonitorState {
  case notStarted
  case waitingForSnapshot
  case available
  case unavailable
}

private enum QuotaMethod {
  static let readRateLimits = "account/rateLimits/read"
  static let rateLimitsUpdated = "account/rateLimits/updated"
}

private struct QuotaMessageHeader: Decodable {
  let id: Int?
  let method: String?
}

private struct RateLimitsResponse: Decodable {
  let result: RateLimitsResult
}

private struct RateLimitsResult: Decodable {
  let rateLimits: RateLimitsPayload
}

private enum RateLimitsPayload: Decodable {
  case legacy([String: RateLimitEntry])
  case bucket(RateLimitBucket)

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let legacy = try? container.decode([String: RateLimitEntry].self) {
      self = .legacy(legacy)
    } else {
      self = .bucket(try container.decode(RateLimitBucket.self))
    }
  }

  var windows: [String: RateLimitEntry] {
    switch self {
    case .legacy(let windows):
      windows
    case .bucket(let bucket):
      bucket.windows
    }
  }
}

private struct RateLimitBucket: Decodable {
  let limitId: String?
  let primary: RateLimitEntry?
  let secondary: RateLimitEntry?

  var windows: [String: RateLimitEntry] {
    let prefix = limitId ?? "default"
    return [
      "\(prefix).primary": primary,
      "\(prefix).secondary": secondary,
    ].compactMapValues { $0 }
  }
}

private struct RateLimitsNotification: Decodable {
  let params: RateLimitsParams
}

private struct RateLimitsParams: Decodable {
  let rateLimits: [String: RateLimitEntry]
}

private struct RateLimitEntry: Decodable {
  let durationSeconds: TimeInterval?
  let usedPercent: Double?
  let resetAt: String?
  let windowDurationMins: TimeInterval?
  let resetsAt: TimeInterval?
}
