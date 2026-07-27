import Foundation

/// Allocates request IDs for every App Server request issued by one Beacon
/// connection. App Server responses are correlated solely by ID, so task and
/// quota monitors must share this sequence.
final class AppServerRequestIDGenerator {
  private var nextRequestID: Int

  init(startingAt startingRequestID: Int = 1) {
    nextRequestID = startingRequestID
  }

  func next() -> Int {
    defer { nextRequestID += 1 }
    return nextRequestID
  }
}
