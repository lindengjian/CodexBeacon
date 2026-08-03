import Foundation
import Testing

@testable import CodexBeacon

struct DesktopDaemonCompatibilityAdapterTests {
  @Test("an adopted integration accepts a future bundled CLI without version gating")
  func acceptsFutureBundledCLIWithoutVersionGating() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("CodexBeaconTests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }

    let launchAgentURL = root.appendingPathComponent("LaunchAgents/shared-app-server.plist")
    let stateURL = root.appendingPathComponent("Application Support/shared-daemon-adoption.json")
    let diagnostics = LocalDiagnosticStore(directory: root.appendingPathComponent("diagnostics"))
    try FileManager.default.createDirectory(
      at: stateURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    var launchctlCalls: [[String]] = []
    let adapter = DesktopDaemonCompatibilityAdapter(
      fileManager: .default,
      diagnosticStore: diagnostics,
      launchAgentURL: launchAgentURL,
      stateURL: stateURL,
      runLaunchctl: { arguments, _ in
        launchctlCalls.append(arguments)
        return ""
      }
    )
    let cliURL = URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex-0.999.0-future")

    #expect(adapter.activateForCurrentLogin(bundledCLIURL: cliURL) == nil)
    #expect(launchctlCalls.map(\.first) == ["getenv", "bootout", "bootstrap", "setenv"])
    launchctlCalls.removeAll()

    #expect(adapter.activateForCurrentLogin(bundledCLIURL: cliURL) == nil)
    #expect(launchctlCalls == [["setenv", "CODEX_APP_SERVER_USE_LOCAL_DAEMON", "1"]])

    let data = try Data(contentsOf: launchAgentURL)
    let plist = try #require(
      PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    )
    let arguments = try #require(plist["ProgramArguments"] as? [String])
    #expect(arguments.prefix(3) == ["/bin/sh", "-c", "/bin/launchctl setenv CODEX_APP_SERVER_USE_LOCAL_DAEMON 1; exec \"$1\" -c \"features.code_mode_host=true\" app-server --listen unix://"])
    #expect(arguments.suffix(2) == ["codexbeacon-sh", cliURL.path])
  }
}
