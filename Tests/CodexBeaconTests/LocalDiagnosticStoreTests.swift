import Foundation
import Testing

@testable import CodexBeacon

struct LocalDiagnosticStoreTests {
  @Test("protocol diagnostics retain only metadata and state summaries")
  func protocolDiagnosticsMinimizePrivateData() {
    let entry = DesktopAppServerMonitor.diagnosticEntry(
      forReceivedMessage: #"{"id":42,"method":"thread/status/changed","params":{"threadId":"task-private-id","threadName":"Quarterly plan — confidential","account":{"email":"owner@example.com"},"localPath":"/Users/owner/Private/project","status":{"type":"active","activeFlags":["waitingOnUserInput"]}}}"#
    )

    #expect(entry.contains("id=42"))
    #expect(entry.contains("method=thread/status/changed"))
    #expect(entry.contains("status_type=active"))
    #expect(entry.contains("active_flags=waitingOnUserInput"))
    #expect(!entry.contains("task-private-id"))
    #expect(!entry.contains("Quarterly plan"))
    #expect(!entry.contains("owner@example.com"))
    #expect(!entry.contains("/Users/owner/Private/project"))
  }

  @Test("quota refresh diagnostics omit server error text")
  func quotaRefreshDiagnosticsMinimizeServerErrorText() {
    let reason = DesktopAppServerMonitor.quotaRefreshErrorReason(
      for: [
        "code": -32,
        "message": "Quarterly plan for owner@example.com at /Users/owner/Private/project",
      ]
    )

    #expect(reason == "server_error code=-32")
    #expect(!reason.contains("Quarterly plan"))
    #expect(!reason.contains("owner@example.com"))
    #expect(!reason.contains("/Users/owner/Private/project"))
  }

  @Test("recording diagnostic data never blocks the caller")
  func recordsAsynchronously() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("CodexBeaconTests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }

    let queue = DispatchQueue(label: "CodexBeaconTests.diagnostic-recording")
    let store = LocalDiagnosticStore(directory: directory, writeQueue: queue)
    store.beginRun(runID: "asynchronous-test")

    queue.suspend()
    defer { queue.resume() }
    store.record("entry written after the caller returns")

    let trace = try String(contentsOf: store.fileURL, encoding: .utf8)
    #expect(!trace.contains("entry written after the caller returns"))
  }

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
    store.flush()

    let trace = try String(contentsOf: store.fileURL, encoding: .utf8)

    #expect(trace.contains("run_id=test-run"))
    #expect(trace.contains("protocol sent id=12 method=thread/loaded/list"))
    #expect(trace.contains("status_after=working"))
    #expect(
      trace.range(of: "thread/loaded/list")!.lowerBound
        < trace.range(of: "status_after=working")!.lowerBound
    )
  }

  @Test("entries older than 5 minutes are pruned by a background flush")
  func prunesEntriesOlderThanRetentionWindow() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("CodexBeaconTests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = LocalDiagnosticStore(directory: directory)
    let now = Date(timeIntervalSince1970: 1_753_500_000)
    store.beginRun(runID: "prune-test", startedAt: now)

    // Write an entry 10 minutes ago — should be pruned after next write.
    store.record("stale entry", at: now.addingTimeInterval(-600))
    // Write an entry 3 minutes ago — should survive.
    store.record("recent entry", at: now.addingTimeInterval(-180))
    // Write a current entry — should survive and trigger pruning.
    store.record("current entry", at: now)
    store.flush()

    let trace = try String(contentsOf: store.fileURL, encoding: .utf8)

    #expect(!trace.contains("stale entry"), "entry older than 5 min should be pruned")
    #expect(trace.contains("recent entry"), "entry within 5 min should survive")
    #expect(trace.contains("current entry"), "current entry should survive")
    #expect(trace.contains("run_id=prune-test"), "header should survive")
  }

  @Test("a diagnostic log can be copied to a user-selected folder without replacing existing exports")
  func exportsDiagnosticLogToSelectedDirectory() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("CodexBeaconTests-\(UUID().uuidString)")
    let sourceDirectory = root.appendingPathComponent("source")
    let exportDirectory = root.appendingPathComponent("exports")
    defer { try? FileManager.default.removeItem(at: root) }

    let store = LocalDiagnosticStore(directory: sourceDirectory)
    store.beginRun(runID: "export-test")
    store.record("coordinator state_resolved status_after=working")
    try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

    let firstExport = try store.export(to: exportDirectory)
    let secondExport = try store.export(to: exportDirectory)

    #expect(firstExport.deletingLastPathComponent().path == exportDirectory.path)
    #expect(secondExport.deletingLastPathComponent().path == exportDirectory.path)
    #expect(firstExport != secondExport)
    #expect(try String(contentsOf: firstExport, encoding: .utf8).contains("run_id=export-test"))
    #expect(try String(contentsOf: secondExport, encoding: .utf8).contains("status_after=working"))
  }
}
