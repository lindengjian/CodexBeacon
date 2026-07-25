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
      let priorValue = launchctlEnvironmentValue()
      try persist(AdoptionState(priorEnvironmentValue: priorValue))
      try writeLaunchAgent(for: bundledCLIURL)
      try runLaunchctl(["bootout", userDomain, Self.label], allowFailure: true)
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
    _ = try? runLaunchctl(["bootout", userDomain, Self.label], allowFailure: true)
    try? fileManager.removeItem(at: launchAgentURL)
    if let state = try? loadState() {
      if let priorValue = state.priorEnvironmentValue {
        _ = try? runLaunchctl(["setenv", Self.environmentKey, priorValue])
      } else {
        _ = try? runLaunchctl(["unsetenv", Self.environmentKey])
      }
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

  private var userDomain: String { "gui/\(getuid())" }

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

  init(fileManager: FileManager = .default) {
    directory = fileManager.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/CodexBeacon")
    fileURL = directory.appendingPathComponent("task-monitoring-diagnostic.txt")
  }

  func createDirectory() throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  func record(_ message: String) {
    try? createDirectory()
    let datedMessage = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
    try? datedMessage.write(to: fileURL, atomically: true, encoding: .utf8)
  }
}
