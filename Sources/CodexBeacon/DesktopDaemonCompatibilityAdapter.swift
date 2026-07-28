import AppKit
import Foundation

/// Owns only the compatibility state created by Codex Beacon. The Desktop
/// daemon flag is undocumented, so this adapter is intentionally version-gated
/// and preserves any pre-existing launchd value for a lossless rollback.
final class DesktopDaemonCompatibilityAdapter {
  private static let label = "com.codexbeacon.shared-app-server"
  private static let environmentKey = "CODEX_APP_SERVER_USE_LOCAL_DAEMON"
  private static let supportedCLIVersions = ["0.146.0-alpha.3.1"]

  private let fileManager: FileManager
  private let diagnosticStore: LocalDiagnosticStore
  private let launchAgentURL: URL
  private let stateURL: URL

  init(fileManager: FileManager = .default, diagnosticStore: LocalDiagnosticStore = .init()) {
    self.fileManager = fileManager
    self.diagnosticStore = diagnosticStore
    launchAgentURL = fileManager.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/LaunchAgents")
      .appendingPathComponent("\(Self.label).plist")
    stateURL = diagnosticStore.directory.appendingPathComponent("shared-daemon-adoption.json")
  }

  /// Installs a user-scoped, labelled daemon and opt-in for the *next* Desktop
  /// process. It never terminates Desktop, because that could discard user work.
  func prepare(bundledCLIURL: URL, cliVersion: String) -> String? {
    guard Self.supportedCLIVersions.contains(cliVersion) else {
      return "Unsupported Codex Desktop CLI \(cliVersion). Shared-daemon adoption was not attempted."
    }

    do {
      try fileManager.createDirectory(
        at: launchAgentURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try diagnosticStore.createDirectory()
      if !fileManager.fileExists(atPath: stateURL.path) {
        let priorValue = launchctlEnvironmentValue()
        try persist(AdoptionState(priorEnvironmentValue: priorValue))
      }
      try writeLaunchAgent(for: bundledCLIURL)
      try runLaunchctl(["bootout", serviceTarget], allowFailure: true)
      try runLaunchctl(["bootstrap", userDomain, launchAgentURL.path])
      try runLaunchctl(["setenv", Self.environmentKey, "1"])
      diagnosticStore.record("Shared-daemon compatibility adapter prepared. Fully quit and reopen Codex Desktop, then reopen Codex Beacon to validate shared runtime state.")
      return nil
    } catch {
      rollback()
      let message = "Shared-daemon adoption failed: \(error.localizedDescription)"
      diagnosticStore.record(message)
      return message
    }
  }

  /// Restores the exact launchd environment value that existed before Beacon
  /// installed its adapter, and removes only Beacon's labelled LaunchAgent.
  func rollback() {
    guard let state = try? loadState() else {
      diagnosticStore.record("Shared-daemon rollback was not attempted because Beacon ownership state is missing or unreadable.")
      return
    }
    _ = try? runLaunchctl(["bootout", serviceTarget], allowFailure: true)
    try? fileManager.removeItem(at: launchAgentURL)
    if let priorValue = state.priorEnvironmentValue {
      _ = try? runLaunchctl(["setenv", Self.environmentKey, priorValue])
    } else {
      _ = try? runLaunchctl(["unsetenv", Self.environmentKey])
    }
    try? fileManager.removeItem(at: stateURL)
    diagnosticStore.record("Shared-daemon compatibility adapter removed. Fully quit and reopen Codex Desktop to restore its default private App Server topology.")
  }

  /// A connection alone is insufficient: Beacon only treats runtime state as
  /// shared after it sees a visible Desktop (`vscode`) loaded thread.
  func sharedRuntimeEvidenceObserved() {
    diagnosticStore.record("Shared-daemon runtime state verified from a loaded Codex Desktop thread.")
  }

  var diagnosticPath: URL { diagnosticStore.fileURL }

  var isPrepared: Bool {
    fileManager.fileExists(atPath: launchAgentURL.path)
      && fileManager.fileExists(atPath: stateURL.path)
  }

  static func supports(cliVersion: String) -> Bool {
    supportedCLIVersions.contains(cliVersion)
  }

  private var userDomain: String { "gui/\(getuid())" }
  private var serviceTarget: String { "\(userDomain)/\(Self.label)" }

  private func writeLaunchAgent(for bundledCLIURL: URL) throws {
    let programArguments = [
      bundledCLIURL.path,
      "-c", "features.code_mode_host=true",
      "app-server", "--listen", "unix://", "--analytics-default-enabled",
    ]
    let plist: [String: Any] = [
      "Label": Self.label,
      "ProgramArguments": programArguments,
      "RunAtLoad": true,
      "KeepAlive": true,
      "ProcessType": "Interactive",
    ]
    let data = try PropertyListSerialization.data(
      fromPropertyList: plist,
      format: .xml,
      options: 0
    )
    try data.write(to: launchAgentURL, options: .atomic)
  }

  private func persist(_ state: AdoptionState) throws {
    let data = try JSONEncoder().encode(state)
    try data.write(to: stateURL, options: .atomic)
  }

  private func loadState() throws -> AdoptionState {
    try JSONDecoder().decode(AdoptionState.self, from: Data(contentsOf: stateURL))
  }

  private func launchctlEnvironmentValue() -> String? {
    guard let output = try? runLaunchctl(["getenv", Self.environmentKey], allowFailure: true) else {
      return nil
    }
    let value = output.trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
  }

  @discardableResult
  private func runLaunchctl(_ arguments: [String], allowFailure: Bool = false) throws -> String {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = output
    try process.run()
    process.waitUntilExit()
    let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    guard allowFailure || process.terminationStatus == 0 else {
      throw CompatibilityError.launchctlFailed(text)
    }
    return text
  }
}

private struct AdoptionState: Codable {
  let priorEnvironmentValue: String?
}

private enum CompatibilityError: LocalizedError {
  case launchctlFailed(String)

  var errorDescription: String? {
    switch self {
    case .launchctlFailed(let output):
      "launchctl failed: \(output.trimmingCharacters(in: .whitespacesAndNewlines))"
    }
  }
}

final class LocalDiagnosticStore {
  let directory: URL
  let fileURL: URL
  private static let writeLock = NSLock()
  private static nonisolated(unsafe) let isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
  }()

  /// Entries older than this duration are pruned on each write.
  private let retentionDuration: TimeInterval = 300 // 5 minutes

  init(
    fileManager: FileManager = .default,
    directory: URL? = nil
  ) {
    self.directory = directory ?? fileManager.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/CodexBeacon")
    fileURL = self.directory.appendingPathComponent("task-monitoring-diagnostic.txt")
  }

  func createDirectory() throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  /// Starts a fresh, self-contained trace for one Beacon process run. All
  /// later entries append to this file, so the final transition before a
  /// failure is retained instead of overwriting earlier evidence.
  func beginRun(runID: String = UUID().uuidString, startedAt: Date = Date()) {
    let header = [
      "# Codex Beacon task-monitoring diagnostic trace",
      "run_id=\(runID)",
      "started_at=\(timestamp(for: startedAt))",
      "format_version=1",
      "",
    ].joined(separator: "\n")

    Self.writeLock.lock()
    defer { Self.writeLock.unlock() }
    do {
      try createDirectory()
      try header.write(to: fileURL, atomically: true, encoding: .utf8)
    } catch {
      // Diagnostics must never interfere with passive task observation.
    }
  }

  func record(_ message: String, at date: Date = Date()) {
    let entry = "\(timestamp(for: date)) \(message)\n"

    Self.writeLock.lock()
    defer { Self.writeLock.unlock() }
    do {
      try createDirectory()
      if FileManager.default.fileExists(atPath: fileURL.path) {
        let handle = try FileHandle(forWritingTo: fileURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(entry.utf8))
        try handle.close()
      } else {
        try entry.write(to: fileURL, atomically: true, encoding: .utf8)
      }
      try pruneEntries(at: date)
    } catch {
      // Diagnostics must never interfere with passive task observation.
    }
  }

  /// Removes entries whose timestamp is older than `retentionDuration`
  /// from `date`. Header lines (those without a parseable ISO8601
  /// timestamp) are always preserved. Since entries are written in
  /// chronological order, we locate the first entry that falls within the
  /// retention window and drop everything before it.
  private func pruneEntries(at date: Date) throws {
    let cutoff = date.addingTimeInterval(-retentionDuration)
    let content = try String(contentsOf: fileURL, encoding: .utf8)
    let lines = content.components(separatedBy: "\n")

    // Split header (non-timestamp lines at the top) from entries.
    var headerEnd = 0
    for line in lines {
      if parseTimestamp(from: line) != nil { break }
      headerEnd += 1
    }
    guard headerEnd < lines.count else { return } // no entries yet

    // Find the first entry >= cutoff (entries are chronological).
    var keepFrom = lines.count
    for i in headerEnd..<lines.count {
      guard let ts = parseTimestamp(from: lines[i]) else { continue }
      if ts >= cutoff {
        keepFrom = i
        break
      }
    }

    // Keep header + entries from keepFrom onwards. When keepFrom ==
    // lines.count (all entries too old), the second slice is empty.
    let kept = Array(lines[0..<headerEnd]) + Array(lines[keepFrom..<lines.count])

    let result = kept.joined(separator: "\n")
    try result.write(to: fileURL, atomically: true, encoding: .utf8)
  }

  /// Returns the ISO8601 timestamp at the start of `line`, or nil.
  private func parseTimestamp(from line: String) -> Date? {
    guard line.count >= 20 else { return nil }
    let prefix = String(line.prefix(while: { $0 != " " }))
    return Self.isoFormatter.date(from: prefix)
  }

  /// Copies the current trace into a user-selected directory. The timestamped
  /// filename, with a numeric suffix if necessary, preserves prior exports.
  func export(to destinationDirectory: URL, at date: Date = Date()) throws -> URL {
    Self.writeLock.lock()
    defer { Self.writeLock.unlock() }

    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      throw DiagnosticLogExportError.logUnavailable
    }

    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(
      atPath: destinationDirectory.path,
      isDirectory: &isDirectory
    ), isDirectory.boolValue else {
      throw DiagnosticLogExportError.destinationIsNotDirectory
    }

    let baseName = "CodexBeacon-diagnostic-\(exportTimestamp(for: date))"
    var sequence = 1
    var destinationURL = destinationDirectory
      .appendingPathComponent("\(baseName).txt")
    while FileManager.default.fileExists(atPath: destinationURL.path) {
      sequence += 1
      destinationURL = destinationDirectory
        .appendingPathComponent("\(baseName)-\(sequence).txt")
    }

    try FileManager.default.copyItem(at: fileURL, to: destinationURL)
    return destinationURL
  }

  private func timestamp(for date: Date) -> String {
    Self.isoFormatter.string(from: date)
  }

  private func exportTimestamp(for date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter.string(from: date)
  }
}

private enum DiagnosticLogExportError: LocalizedError {
  case logUnavailable
  case destinationIsNotDirectory

  var errorDescription: String? {
    switch self {
    case .logUnavailable:
      "当前没有可导出的诊断日志。请先启动 Beacon 并复现问题。"
    case .destinationIsNotDirectory:
      "请选择一个用于保存日志的文件夹。"
    }
  }
}
