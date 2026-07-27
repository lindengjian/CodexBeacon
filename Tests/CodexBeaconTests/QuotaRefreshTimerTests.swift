import Foundation
import Testing

@testable import CodexBeacon

@MainActor
struct QuotaRefreshTimerTests {
  @Test("a running quota timer immediately adopts a shorter working interval")
  func quotaTimerAdoptsShorterInterval() async throws {
    let recorder = TimerFireRecorder()
    let timer = QuotaRefreshTimer(
      interval: 0.2,
      leeway: .milliseconds(1)
    ) {
      recorder.recordFire()
    }
    defer { timer.stop() }

    timer.start()
    try await Task.sleep(for: .milliseconds(20))
    timer.update(interval: 0.02)
    try await Task.sleep(for: .milliseconds(75))

    #expect(recorder.fireCount >= 2)
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
    try await Task.sleep(for: .milliseconds(45))
    timer.stop()
    let firesBeforeWait = recorder.fireCount
    try await Task.sleep(for: .milliseconds(45))

    #expect(firesBeforeWait > 0)
    #expect(recorder.fireCount == firesBeforeWait)
  }
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
