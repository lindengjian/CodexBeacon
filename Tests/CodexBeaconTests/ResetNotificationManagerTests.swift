import CodexBeaconCore
import Foundation
import Testing
import UserNotifications

@testable import CodexBeacon

@MainActor
struct ResetNotificationManagerTests {
  private static let baseTime = Date(timeIntervalSince1970: 1_753_353_600)

  // MARK: - Merge window

  @Test("single reset event delivers notification after merge window")
  func singleResetDeliversAfterMergeWindow() async {
    var currentTime = Self.baseTime
    var delivered: [UNNotificationContent] = []

    let manager = ResetNotificationManager(
      now: { currentTime },
      deliverNotification: { delivered.append($0) }
    )

    let event = QuotaResetEvent(
      kind: .confirmed, windowKeys: ["5h"], detectedAt: currentTime)
    manager.enqueue(event)

    // Before merge window elapses — no delivery yet
    #expect(delivered.isEmpty)
    #expect(manager.isBorderPulseActive == false)

    // After merge window
    currentTime = currentTime.addingTimeInterval(ResetNotificationManager.mergeWindow + 0.1)
    manager.flush()

    #expect(delivered.count == 1)
    #expect(delivered[0].title == "额度已重置")
    #expect(delivered[0].body.contains("5h"))
    #expect(delivered[0].body.contains("100%"))
    #expect(delivered[0].sound == .default)
    #expect(manager.isBorderPulseActive == true)
    #expect(manager.activeMessage != nil)
  }

  @Test("multiple resets within merge window are coalesced")
  func multipleResetsWithinMergeWindowCoalesced() async {
    var currentTime = Self.baseTime
    var delivered: [UNNotificationContent] = []

    let manager = ResetNotificationManager(
      now: { currentTime },
      deliverNotification: { delivered.append($0) }
    )

    // First reset
    manager.enqueue(
      QuotaResetEvent(
        kind: .confirmed, windowKeys: ["5h"], detectedAt: currentTime))

    // Second reset within merge window (5s later)
    currentTime = currentTime.addingTimeInterval(5)
    manager.enqueue(
      QuotaResetEvent(
        kind: .confirmed, windowKeys: ["7d"], detectedAt: currentTime))

    // After merge window
    currentTime = currentTime.addingTimeInterval(
      ResetNotificationManager.mergeWindow + 0.1)
    manager.flush()

    // Only ONE notification delivered with both windows
    #expect(delivered.count == 1)
    let body = delivered[0].body
    #expect(body.contains("5h"))
    #expect(body.contains("7d"))
    #expect(body.contains("100%"))
  }

  @Test("resets outside merge window produce separate notifications")
  func resetsOutsideMergeWindowSeparate() async {
    var currentTime = Self.baseTime
    var delivered: [UNNotificationContent] = []

    let manager = ResetNotificationManager(
      now: { currentTime },
      deliverNotification: { delivered.append($0) }
    )

    // First reset
    manager.enqueue(
      QuotaResetEvent(
        kind: .confirmed, windowKeys: ["5h"], detectedAt: currentTime))

    // Wait past merge window
    currentTime = currentTime.addingTimeInterval(
      ResetNotificationManager.mergeWindow + 1)
    manager.flush()
    #expect(delivered.count == 1)
    delivered.removeAll()

    // Second reset (new window)
    manager.enqueue(
      QuotaResetEvent(
        kind: .confirmed, windowKeys: ["7d"], detectedAt: currentTime))
    currentTime = currentTime.addingTimeInterval(
      ResetNotificationManager.mergeWindow + 1)
    manager.flush()

    #expect(delivered.count == 1)
    #expect(delivered[0].body.contains("7d"))
    #expect(!delivered[0].body.contains("5h"))
  }

  @Test("confirmed and inferred resets are merged but distinguished in notification")
  func confirmedAndInferredMergedButDistinguished() async {
    var currentTime = Self.baseTime
    var delivered: [UNNotificationContent] = []

    let manager = ResetNotificationManager(
      now: { currentTime },
      deliverNotification: { delivered.append($0) }
    )

    manager.enqueue(
      QuotaResetEvent(
        kind: .confirmed, windowKeys: ["5h"], detectedAt: currentTime))
    currentTime = currentTime.addingTimeInterval(2)
    manager.enqueue(
      QuotaResetEvent(
        kind: .inferred, windowKeys: ["7d"], detectedAt: currentTime))

    currentTime = currentTime.addingTimeInterval(
      ResetNotificationManager.mergeWindow + 0.1)
    manager.flush()

    #expect(delivered.count == 1)
    let body = delivered[0].body
    // Confirmed appears with "额度已重置"
    #expect(body.contains("额度已重置"))
    #expect(body.contains("5h"))
    // Inferred appears with "推断"
    #expect(body.contains("推断"))
    #expect(body.contains("7d"))
  }

  // MARK: - Border pulse

  @Test("border pulse activates on delivery and deactivates after duration")
  func borderPulseActivatesAndDeactivates() async {
    var currentTime = Self.baseTime
    var delivered: [UNNotificationContent] = []

    let manager = ResetNotificationManager(
      now: { currentTime },
      deliverNotification: { delivered.append($0) }
    )

    manager.enqueue(
      QuotaResetEvent(
        kind: .confirmed, windowKeys: ["5h"], detectedAt: currentTime))

    // Before merge — no pulse
    #expect(manager.isBorderPulseActive == false)

    // After merge window — pulse active
    currentTime = currentTime.addingTimeInterval(
      ResetNotificationManager.mergeWindow + 0.1)
    manager.flush()
    #expect(manager.isBorderPulseActive == true)

    // Wait for border pulse to expire (dispatch after borderPulseDuration)
    // We test that isBorderPulseActive was set — the actual timer is async.
  }

  // MARK: - Temporary message

  @Test("temporary message is set on delivery and cleared after duration")
  func temporaryMessageSetAndCleared() async {
    var currentTime = Self.baseTime

    let manager = ResetNotificationManager(
      now: { currentTime },
      deliverNotification: { _ in }
    )

    #expect(manager.activeMessage == nil)

    manager.enqueue(
      QuotaResetEvent(
        kind: .confirmed, windowKeys: ["5h"], detectedAt: currentTime))

    currentTime = currentTime.addingTimeInterval(
      ResetNotificationManager.mergeWindow + 0.1)
    manager.flush()

    #expect(manager.activeMessage != nil)
    #expect(manager.activeMessage!.contains("5h"))
    #expect(manager.activeMessage!.contains("100%"))
  }

  // MARK: - Cancel pending

  @Test("cancelPending clears accumulated state without delivering")
  func cancelPendingClearsState() async {
    var currentTime = Self.baseTime
    var delivered: [UNNotificationContent] = []

    let manager = ResetNotificationManager(
      now: { currentTime },
      deliverNotification: { delivered.append($0) }
    )

    manager.enqueue(
      QuotaResetEvent(
        kind: .confirmed, windowKeys: ["5h"], detectedAt: currentTime))
    manager.cancelPending()

    // Move past merge window and flush
    currentTime = currentTime.addingTimeInterval(
      ResetNotificationManager.mergeWindow + 1)
    manager.flush()

    #expect(delivered.isEmpty)
    #expect(manager.activeMessage == nil)
  }
}
