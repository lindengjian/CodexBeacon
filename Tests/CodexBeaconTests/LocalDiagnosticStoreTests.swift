import Foundation
import Testing

@testable import CodexBeacon

struct LocalDiagnosticStoreTests {
  @Test("a diagnostic run keeps every entry in chronological order")
  func recordsEntireDiagnosticRun() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("CodexBeaconTests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = LocalDiagnosticStore(directory: directory)
    let start = Date(timeIntervalSince1970: 1_753_500_000)
    store.beginRun(runID: "test-run", startedAt: start)
    store.record("protocol sent id=12 method=thread/loaded/list", at: start.addingTimeInterval(1))
    store.record(
      "coordinator state_resolved status_after=working working=1 waiting=0 completed=0 visible=true",
      at: start.addingTimeInterval(2)
    )

    let trace = try String(contentsOf: store.fileURL, encoding: .utf8)

    #expect(trace.contains("run_id=test-run"))
    #expect(trace.contains("protocol sent id=12 method=thread/loaded/list"))
    #expect(trace.contains("status_after=working"))
    #expect(
      trace.range(of: "thread/loaded/list")!.lowerBound
        < trace.range(of: "status_after=working")!.lowerBound
    )
  }
}
