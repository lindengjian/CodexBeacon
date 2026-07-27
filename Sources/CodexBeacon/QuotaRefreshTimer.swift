import Foundation

/// Owns the Dispatch timer used to request fresh account quota snapshots.
/// Keeping this lifecycle separate makes interval changes observable and
/// directly testable without a live App Server connection.
final class QuotaRefreshTimer: @unchecked Sendable {
  private let queue: DispatchQueue
  private let leeway: DispatchTimeInterval
  private let handler: @Sendable () -> Void
  private var timer: DispatchSourceTimer?
  private var interval: TimeInterval

  init(
    interval: TimeInterval,
    queue: DispatchQueue = .main,
    leeway: DispatchTimeInterval = .milliseconds(500),
    handler: @escaping @Sendable () -> Void
  ) {
    self.interval = interval
    self.queue = queue
    self.leeway = leeway
    self.handler = handler
  }

  func start() {
    guard timer == nil else { return }
    schedule()
  }

  func update(interval: TimeInterval) {
    guard self.interval != interval else { return }
    self.interval = interval
    guard timer != nil else { return }
    stop()
    schedule()
  }

  func stop() {
    timer?.cancel()
    timer = nil
  }

  private func schedule() {
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now() + interval, repeating: interval, leeway: leeway)
    timer.setEventHandler(handler: handler)
    self.timer = timer
    timer.resume()
  }
}
