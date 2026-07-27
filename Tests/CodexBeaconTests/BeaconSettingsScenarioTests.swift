import AppKit
import Testing

@testable import CodexBeacon
@testable import CodexBeaconCore

@MainActor
struct BeaconSettingsScenarioTests {
  @Test("initial setup defaults launch at login on and preserves the user's choice when completed")
  func initialSetupPersistsSelectedLaunchAtLoginChoice() {
    var completedLaunchAtLogin: Bool?
    let diagnostic = DesktopIntegrationDiagnostic(
      health: .ready,
      summary: "兼容",
      instructions: "可开始监测。"
    )
    let setup = InitialSetupModel(
      notificationStatus: "尚未请求",
      diagnostic: diagnostic,
      requestNotificationPermission: { completion in completion("已允许") },
      diagnose: { completion in completion(diagnostic) },
      repair: { completion in completion(diagnostic) },
      complete: {
        completedLaunchAtLogin = $0
        return nil
      }
    )

    #expect(setup.launchesAtLogin)

    setup.launchesAtLogin = false
    setup.finish()

    #expect(completedLaunchAtLogin == false)
  }

  @Test("initial setup keeps the user in setup when launch-at-login registration fails")
  func initialSetupShowsLaunchAtLoginFailure() {
    let diagnostic = DesktopIntegrationDiagnostic(
      health: .ready,
      summary: "兼容",
      instructions: "可开始监测。"
    )
    let setup = InitialSetupModel(
      notificationStatus: "尚未请求",
      diagnostic: diagnostic,
      requestNotificationPermission: { completion in completion("已允许") },
      diagnose: { completion in completion(diagnostic) },
      repair: { completion in completion(diagnostic) },
      complete: { _ in "无法更新登录启动。" }
    )

    setup.finish()

    #expect(setup.completionError == "无法更新登录启动。")
  }

  @Test("settings can persist a changed launch-at-login choice and refresh local diagnostics")
  func integrationSettingsRefreshesDiagnosticsAndPersistsLoginChoice() {
    var persistedLaunchAtLogin: Bool?
    let exportURL = URL(fileURLWithPath: "/tmp/CodexBeacon-diagnostic.txt")
    let diagnostic = DesktopIntegrationDiagnostic(
      health: .ready,
      summary: "兼容",
      instructions: "可开始监测。"
    )
    let settings = BeaconIntegrationSettingsModel(
      launchesAtLogin: true,
      notificationStatus: "尚未请求",
      diagnostic: .init(health: .repairRequired, summary: "尚未检测", instructions: "请检测。"),
      setLaunchAtLogin: { _ in nil },
      requestNotificationPermission: { completion in completion("已允许") },
      readNotificationStatus: { completion in completion("已允许") },
      diagnose: { completion in completion(diagnostic) },
      repair: { completion in completion(diagnostic) },
      restoreDefaultIntegration: { completion in completion(diagnostic) },
      persistLaunchAtLogin: { persistedLaunchAtLogin = $0 },
      exportDiagnosticLog: { .exported(exportURL) }
    )

    settings.updateLaunchAtLogin(false)
    settings.refresh()
    settings.exportDiagnosticLog()

    #expect(!settings.launchesAtLogin)
    #expect(persistedLaunchAtLogin == false)
    #expect(settings.diagnostic == diagnostic)
    #expect(settings.diagnosticLogExportStatus == "已导出到：\(exportURL.path)")
  }

  @Test("settings size selection updates the actual Beacon panel and its global hotkey still toggles visibility")
  func settingsSelectionUpdatesPanelAndHotKeyBehavior() {
    _ = NSApplication.shared
    let coordinator = AppCoordinator()
    let display = BeaconDisplay(
      identifier: "built-in",
      safeFrame: .init(x: 0, y: 24, width: 1_440, height: 876)
    )
    let panel = BeaconPanel(
      state: coordinator.viewState,
      onActivate: {},
      onDragEnded: {}
    )
    defer { panel.close() }

    coordinator.handle(
      .system(.displayLayoutChanged(.init(primaryDisplayIdentifier: "built-in", displays: [display])))
    )
    _ = coordinator.drainEffects()

    var registeredHotKey: BeaconHotKey?
    var registeredHandler: (() -> Void)?
    let customHotKey = BeaconHotKey(keyCode: 12, modifiers: 4_352)
    let settings = BeaconSettingsModel(
      size: .standard,
      hotKey: .init(keyCode: 8, modifiers: 6_400),
      registrationError: nil,
      onSizeSelected: { coordinator.handle(.user(.beaconSizeSelected($0))) },
      onHotKeySelected: { hotKey in
        registeredHotKey = hotKey
        registeredHandler = { coordinator.handle(.system(.globalHotKeyPressed)) }
        return nil
      }
    )

    settings.selectSize(.compact)
    guard case .placeBeacon(let placement) = coordinator.drainEffects().only else {
      Issue.record("Selecting a size must place the Beacon")
      return
    }
    panel.update(state: coordinator.viewState)
    panel.apply(placement)

    #expect(panel.frame.size == NSSize(width: 24, height: 88))

    #expect(settings.recordHotKey(customHotKey) == nil)
    #expect(registeredHotKey == customHotKey)
    registeredHandler?()
    #expect(coordinator.drainEffects() == [.hideBeacon])
  }
}

private extension Array {
  var only: Element? {
    count == 1 ? first : nil
  }
}
