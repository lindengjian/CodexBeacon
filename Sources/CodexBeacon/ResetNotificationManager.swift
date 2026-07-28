import CodexBeaconCore
import Foundation
import os
import UserNotifications

/// Processes quota-reset events and delivers a single combined notification
/// when multiple windows reset within a short merge window.
///
/// The manager is deliberately clock-injectable so tests can advance time
/// deterministically without waiting for real wall-clock intervals.
@MainActor
final class ResetNotificationManager: @unchecked Sendable {
  /// The merge window in seconds. Multiple resets occurring within this
  /// interval are coalesced into a single notification.
  static let mergeWindow: TimeInterval = 10

  /// Duration of the border pulse animation.
  static let borderPulseDuration: TimeInterval = 5

  /// Duration the temporary reset message remains visible.
  static let messageDuration: TimeInterval = 5

  private let diagnosticStore: LocalDiagnosticStore
  private let now: () -> Date
  private let deliverNotification: @MainActor @Sendable (UNNotificationContent) -> Void

  /// Reset events accumulated within the current merge window, keyed by kind.
  private var pendingConfirmedKeys: Set<String> = []
  private var pendingInferredKeys: Set<String> = []
  private var mergeWindowOpenedAt: Date?
  private var deliveryWorkItem: DispatchWorkItem?

  /// Whether a border pulse is currently active.
  private(set) var isBorderPulseActive = false

  /// The current temporary reset message, if any.
  private(set) var activeMessage: String?

  init(
    diagnosticStore: LocalDiagnosticStore = .init(),
    now: @escaping () -> Date = { Date() },
    deliverNotification: @escaping @MainActor @Sendable (UNNotificationContent) -> Void = {
      ResetNotificationManager.deliverUserNotification($0)
    }
  ) {
    self.diagnosticStore = diagnosticStore
    self.now = now
    self.deliverNotification = deliverNotification
  }

  /// Enqueues a reset event. If this is the first event in a new merge
  /// window, schedules delivery at the end of the window. Otherwise the
  /// event is merged into the pending batch.
  func enqueue(_ event: QuotaResetEvent) {
    let currentTime = now()

    if let openedAt = mergeWindowOpenedAt,
      currentTime.timeIntervalSince(openedAt) < Self.mergeWindow
    {
      // Still within the merge window — accumulate.
      accumulate(event)
      diagnosticStore.record(
        "reset_notification merged kind=\(event.kind) windows=\(event.windowKeys.joined(separator: ",")) pending_confirmed=\(pendingConfirmedKeys.count) pending_inferred=\(pendingInferredKeys.count)"
      )
      return
    }

    // Outside the merge window (or first event) — deliver previous batch
    // and start a new window.
    deliverPendingBatch()
    mergeWindowOpenedAt = currentTime
    accumulate(event)

    // Schedule delivery at the end of the merge window.
    let workItem = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.deliverPendingBatch()
    }
    deliveryWorkItem?.cancel()
    deliveryWorkItem = workItem
    DispatchQueue.main.asyncAfter(
      deadline: .now() + Self.mergeWindow,
      execute: workItem
    )
    diagnosticStore.record(
      "reset_notification window_opened kind=\(event.kind) windows=\(event.windowKeys.joined(separator: ","))"
    )
  }

  /// Delivers any pending merged batch immediately, cancelling the scheduled
  /// delivery. Used by tests to flush without waiting.
  func flush() {
    deliveryWorkItem?.cancel()
    deliveryWorkItem = nil
    deliverPendingBatch()
  }

  /// Cancels any pending delivery without sending a notification.
  func cancelPending() {
    deliveryWorkItem?.cancel()
    deliveryWorkItem = nil
    pendingConfirmedKeys.removeAll()
    pendingInferredKeys.removeAll()
    mergeWindowOpenedAt = nil
  }

  // MARK: - Private

  private func accumulate(_ event: QuotaResetEvent) {
    switch event.kind {
    case .confirmed:
      pendingConfirmedKeys.formUnion(event.windowKeys)
    case .inferred:
      pendingInferredKeys.formUnion(event.windowKeys)
    }
  }

  private func deliverPendingBatch() {
    defer {
      pendingConfirmedKeys.removeAll()
      pendingInferredKeys.removeAll()
      mergeWindowOpenedAt = nil
    }

    let hasConfirmed = !pendingConfirmedKeys.isEmpty
    let hasInferred = !pendingInferredKeys.isEmpty
    guard hasConfirmed || hasInferred else {
      return
    }

    // Build the notification content.
    var parts: [String] = []
    if hasConfirmed {
      let list = pendingConfirmedKeys.sorted().joined(separator: "、")
      parts.append("额度已重置\n\(list) 100%")
    }
    if hasInferred {
      let list = pendingInferredKeys.sorted().joined(separator: "、")
      parts.append("推断额度恢复 · \(list)")
    }

    let body = parts.joined(separator: "；")
    let title = hasConfirmed ? "额度已重置" : "额度变化"

    diagnosticStore.record(
      "reset_notification delivering title=\(title) body=\(body) confirmed=\(pendingConfirmedKeys.sorted().joined(separator: ",")) inferred=\(pendingInferredKeys.sorted().joined(separator: ","))"
    )

    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    if #available(macOS 15, *) {
      content.interruptionLevel = .timeSensitive
    }

    isBorderPulseActive = true
    activeMessage = body

    deliverNotification(content)

    // Schedule border pulse deactivation.
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.borderPulseDuration) { [weak self] in
      self?.isBorderPulseActive = false
    }

    // Schedule message clear.
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.messageDuration) { [weak self] in
      self?.activeMessage = nil
    }
  }

  private static func deliverUserNotification(_ content: UNNotificationContent) {
    let request = UNNotificationRequest(
      identifier: "codex-beacon-quota-reset-\(UUID().uuidString)",
      content: content,
      trigger: nil
    )
    UNUserNotificationCenter.current().add(request) { error in
      if let error {
        Logger(
          subsystem: "com.codexbeacon", category: "reset-notification"
        ).error(
          "Failed to deliver reset notification: \(error.localizedDescription, privacy: .public)"
        )
      }
    }
  }
}
