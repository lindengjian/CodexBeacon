import Foundation
import Testing

@testable import CodexBeacon

@Suite(.serialized)
@MainActor
struct QuotaRefreshTimerTests {
  @Test("a running quota timer immediately adopts a shorter working interval")
  func quotaTimerAdoptsShorterInterval() async throws {
    let recorder = TimerFireRecorder()
    let timer = QuotaRefreshTimer(
      interval: 1,
      queue: DispatchQueue(label: "QuotaRefreshTimerTests.interval"),
      leeway: .milliseconds(1)
    ) {
      recorder.recordFire()
    }
    defer { timer.stop() }

    timer.start()
    try await Task.sleep(for: .milliseconds(20))
    timer.update(interval: 0.02)

    let firedTwice = try await waitForTimerFires(
      timeout: .milliseconds(300),
      condition: { recorder.fireCount >= 2 }
    )

    #expect(firedTwice)
  }

  @Test("a stopped quota timer no longer emits refresh events")
  func stoppedQuotaTimerDoesNotEmitRefreshEvents() async throws {
    let recorder = TimerFireRecorder()
    let timer = QuotaRefreshTimer(
      interval: 0.015,
      leeway: .milliseconds(1)
    ) {
      recorder.recordFire()
    }

    timer.start()
    let fired = try await waitForTimerFires(
      timeout: .milliseconds(300),
      condition: { recorder.fireCount > 0 }
    )
    timer.stop()
    let firesBeforeWait = recorder.fireCount
    try await Task.sleep(for: .milliseconds(100))

    #expect(fired)
    #expect(recorder.fireCount == firesBeforeWait)
  }
}

private func waitForTimerFires(
  timeout: Duration,
  condition: @escaping @Sendable () -> Bool
) async throws -> Bool {
  let clock = ContinuousClock()
  let deadline = clock.now + timeout

  while !condition() {
    guard clock.now < deadline else {
      return false
    }
    try await Task.sleep(for: .milliseconds(5))
  }

  return true
}

private final class TimerFireRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var fires = 0

  var fireCount: Int {
    lock.withLock { fires }
  }

  func recordFire() {
    lock.withLock { fires += 1 }
  }
}
