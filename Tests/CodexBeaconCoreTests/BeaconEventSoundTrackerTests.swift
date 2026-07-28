import Testing

@testable import CodexBeaconCore

struct BeaconEventSoundTrackerTests {
  @Test("new waiting and completion events play once per appearance")
  func deduplicatesRepeatedSnapshotsAndAllowsLaterReentry() {
    var tracker = BeaconEventSoundTracker()

    #expect(tracker.observe(waitingTaskIDs: ["waiting-1"], unconfirmedCompletionTaskIDs: []) == [.waiting])
    #expect(tracker.observe(waitingTaskIDs: ["waiting-1"], unconfirmedCompletionTaskIDs: []) == [])
    #expect(tracker.observe(waitingTaskIDs: [], unconfirmedCompletionTaskIDs: ["done-1"]) == [.completion])
    #expect(tracker.observe(waitingTaskIDs: [], unconfirmedCompletionTaskIDs: ["done-1"]) == [])
    #expect(tracker.observe(waitingTaskIDs: [], unconfirmedCompletionTaskIDs: []) == [])
    #expect(tracker.observe(waitingTaskIDs: ["waiting-1"], unconfirmedCompletionTaskIDs: []) == [.waiting])
  }

  @Test("additional tasks in an active category produce one new category event")
  func reportsNewTaskWhileCategoryIsAlreadyActive() {
    var tracker = BeaconEventSoundTracker()

    _ = tracker.observe(waitingTaskIDs: ["waiting-1"], unconfirmedCompletionTaskIDs: [])

    #expect(
      tracker.observe(
        waitingTaskIDs: ["waiting-1", "waiting-2"],
        unconfirmedCompletionTaskIDs: ["done-1", "done-2"]
      ) == [.waiting, .completion]
    )
  }
}
