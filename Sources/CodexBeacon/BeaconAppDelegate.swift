import AppKit
import Carbon
import CodexBeaconCore
import SwiftUI

@MainActor
final class BeaconAppDelegate: NSObject, NSApplicationDelegate {
  private static let defaultHotKey = BeaconHotKey(
    keyCode: UInt32(kVK_ANSI_C),
    modifiers: UInt32(controlKey | optionKey | cmdKey)
  )

  private let preferencesStore = BeaconPreferencesStore()
  private let diagnosticStore = LocalDiagnosticStore()
  private lazy var preferences = preferencesStore.load(fallbackHotKey: Self.defaultHotKey)
  private lazy var coordinator = AppCoordinator(
    requiresSharedRuntimeEvidence: true,
    initialBeaconAnchor: preferences.anchor,
    initialBeaconSize: preferences.size,
    showTaskTitles: preferences.showTaskTitles
  )
  private var panel: BeaconPanel?
  private var taskMonitor: DesktopAppServerMonitor?
  private var screenParametersObserver: NSObjectProtocol?
  private var frontmostAppObserver: NSObjectProtocol?
  private var accessibilityDisplayOptionsObserver: NSObjectProtocol?
  private var codexBundleID = "com.anthropic.codex"
  private var hotKeyReference: EventHotKeyRef?
  private var hotKeyEventHandlerReference: EventHandlerRef?
  private var settingsWindowController: BeaconSettingsWindowController?
  private var setupWindowController: InitialSetupWindowController?
  private var integrationSettingsModel: BeaconIntegrationSettingsModel?
  private var hotKeyRegistrationError: String?
  private var hasStartedMonitoring = false
  private var eventSoundTracker = BeaconEventSoundTracker()
  private lazy var resetNotificationManager = ResetNotificationManager(
    diagnosticStore: diagnosticStore,
    quotaResetSoundSetting: { [weak self] in
      self?.preferences.soundPreferences[.quotaReset]
        ?? .init(isEnabled: true, soundName: "Ping")
    },
    onDelivery: { [weak self] message in
      self?.presentResetDelivery(message)
    }
  )

  func applicationDidFinishLaunching(_ notification: Notification) {
    coordinator.start()
    coordinator.autoConfirmCondition = { [weak self] in
      self?.canAutoConfirmCompletion() ?? false
    }
    present(coordinator.viewState)
    updateReduceMotion()
    perform(coordinator.drainEffects())
    updateDisplayLayout()
    screenParametersObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.updateDisplayLayout()
      }
    }
    frontmostAppObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
        as? NSRunningApplication
      Task { @MainActor [weak self] in
        self?.handleFrontmostAppChange(for: app)
      }
    }
    accessibilityDisplayOptionsObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.updateReduceMotion()
      }
    }
    taskMonitor = DesktopAppServerMonitor(
      deliver: { [weak self] event in self?.handleTaskEvent(event) },
      requestsProvider: { [weak self] in self?.coordinator.drainAppServerRequests() ?? [] },
      diagnosticStore: diagnosticStore
    )
    installGlobalHotKeyEventHandler()
    let status = registerGlobalHotKey(preferences.hotKey)
    if status != noErr {
      hotKeyRegistrationError = "无法注册已保存的全局快捷键（系统错误 \(status)）。请在设置中选择其他快捷键。"
      showSettings()
    }
    if preferences.hasCompletedInitialSetup {
      startMonitoring()
    } else {
      showInitialSetup()
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    diagnosticStore.flush()
    if let screenParametersObserver {
      NotificationCenter.default.removeObserver(screenParametersObserver)
    }
    if let frontmostAppObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(frontmostAppObserver)
    }
    if let accessibilityDisplayOptionsObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(accessibilityDisplayOptionsObserver)
    }
    unregisterGlobalHotKey()
  }

  private func handleTaskEvent(_ event: TaskEvent) {
    let statusBefore = coordinator.viewState.status
    diagnosticStore.record(
      "coordinator handling event=\(event.traceDescription) status_before=\(statusBefore.traceName)"
    )
    let now = Date()
    coordinator.handle(.time(.advanced(to: now)))
    coordinator.handle(.task(event))
    let state = coordinator.viewState
    let completionSoundEvent = coordinator.drainCompletionSoundEvent()
    let hoverDetail = state.hoverDetail
    diagnosticStore.record(
      "coordinator state_resolved status_after=\(state.status.traceName) working=\(hoverDetail?.workingCount ?? 0) waiting=\(hoverDetail?.waitingCount ?? 0) completed=\(hoverDetail?.completedCount ?? 0) visible=\(state.isVisible)"
    )
    taskMonitor?.updateQuotaRefreshInterval(for: coordinator.viewState.status)
    playTaskSounds(for: state, completionSoundEvent: completionSoundEvent)

    // Process reset events without touching task-status lights.
    let resetEvents = coordinator.drainViewResetEvents()
    if !resetEvents.isEmpty {
      diagnosticStore.record(
        "reset_notification events_drained count=\(resetEvents.count) kinds=\(resetEvents.map { $0.kind == .confirmed ? "confirmed" : "inferred" }.joined(separator: ","))"
      )
      for event in resetEvents {
        resetNotificationManager.enqueue(event)
      }
    }

    // Clear expired reset message on state.
    coordinator.clearExpiredResetMessage(now: now)

    updatePanelContent()
  }

  private func present(_ state: BeaconViewState) {
    let panel = BeaconPanel(
      state: state,
      onActivate: { [weak self] in self?.handleBeaconActivation() },
      onDragEnded: { [weak self] in self?.handleBeaconDragEnd() }
    )
    panel.onRightClick = { [weak self] event in
      guard let self else { return }
      self.presentContextMenu(for: panel, with: event)
    }
    self.panel = panel
    panel.center()
  }

  private func perform(_ effects: [BeaconEffect]) {
    for effect in effects {
      switch effect {
      case .showBeacon:
        panel?.orderFrontRegardless()
      case .hideBeacon:
        panel?.orderOut(nil)
      case .activateCodex(let threadID):
        activateCodex(threadID: threadID)
      case .placeBeacon(let placement):
        preferences.anchor = placement.anchor
        preferencesStore.save(preferences)
        updatePanelContent()
        panel?.apply(placement)
      }
    }
  }

  private func handleBeaconActivation() {
    coordinator.handle(.user(.beaconActivated))
    applyCoordinatorUpdate()
  }

  private func handleBeaconDragEnd() {
    guard let panel, let screen = panel.screen else {
      return
    }

    coordinator.handle(
      .user(
        .beaconDragEnded(
          displayIdentifier: displayIdentifier(for: screen),
          frame: beaconRect(from: panel.frame)
        )
      )
    )
    applyCoordinatorUpdate()
  }

  private func updateDisplayLayout() {
    let screens = NSScreen.screens
    guard let primaryScreen = screens.first else {
      return
    }

    let displays = screens.map {
      BeaconDisplay(
        identifier: displayIdentifier(for: $0),
        safeFrame: beaconRect(from: safeFrame(for: $0))
      )
    }
    coordinator.handle(
      .system(
        .displayLayoutChanged(
          .init(
            primaryDisplayIdentifier: displayIdentifier(for: primaryScreen),
            displays: displays
          )
        )
      )
    )
    applyCoordinatorUpdate()
  }

  private func updatePanelContent() {
    let state = coordinator.viewState
    panel?.update(state: state)
    diagnosticStore.record(
      "ui panel_updated status=\(state.status.traceName) amber=\(state.lights[1].illumination.traceName) visible=\(state.isVisible) show_task_titles=\(state.showTaskTitles) hover_tasks=\(state.hoverDetail?.tasks.count ?? 0) hover_show_titles=\(state.hoverDetail?.showTaskTitles ?? false)"
    )
  }

  private func updateReduceMotion() {
    let reducesMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    coordinator.handle(.system(.reduceMotionChanged(reducesMotion)))
    panel?.updateBorderPulse(
      isActive: resetNotificationManager.isBorderPulseActive,
      reducesMotion: reducesMotion
    )
    updatePanelContent()
  }

  private func playTaskSounds(for state: BeaconViewState, completionSoundEvent: Bool) {
    var events = eventSoundTracker.observe(
      waitingTaskIDs: Set(state.waitingTasks.map(\.threadID)),
      unconfirmedCompletionTaskIDs: state.unconfirmedCompletionTaskIDs
    )
    if completionSoundEvent, !events.contains(.completion) {
      events.append(.completion)
    }
    for event in events {
      let setting = preferences.soundPreferences[event]
      guard setting.isEnabled else { continue }
      BeaconSystemSound.play(named: setting.soundName)
    }
  }

  private func presentResetDelivery(_ message: String) {
    let now = Date()
    coordinator.applyResetMessage(
      message,
      expiresAt: now.addingTimeInterval(ResetNotificationManager.messageDuration)
    )
    panel?.updateBorderPulse(
      isActive: resetNotificationManager.isBorderPulseActive,
      reducesMotion: coordinator.viewState.reducesMotion
    )
    updatePanelContent()
  }

  // MARK: - Global Hotkey

  private func installGlobalHotKeyEventHandler() {
    guard hotKeyEventHandlerReference == nil else {
      return
    }
    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: OSType(kEventHotKeyPressed)
    )

    let selfPtr = Unmanaged.passUnretained(self).toOpaque()

    InstallEventHandler(
      GetApplicationEventTarget(),
      { (_, _, userData) -> OSStatus in
        guard let userData else { return OSStatus(eventNotHandledErr) }
        let delegate = Unmanaged<BeaconAppDelegate>.fromOpaque(userData)
          .takeUnretainedValue()
        DispatchQueue.main.async {
          delegate.toggleBeaconVisibility()
        }
        return noErr
      },
      1,
      &eventType,
      selfPtr,
      &hotKeyEventHandlerReference
    )

  }

  @discardableResult
  private func registerGlobalHotKey(_ hotKey: BeaconHotKey) -> OSStatus {
    let hotKeyID = EventHotKeyID(signature: 0x4344_424B, id: 1)  // 'CDBK'
    let status = RegisterEventHotKey(
      hotKey.keyCode,
      hotKey.modifiers,
      hotKeyID,
      GetApplicationEventTarget(),
      0,
      &hotKeyReference
    )

    if status != noErr {
      hotKeyReference = nil
    }
    return status
  }

  private func unregisterRegisteredGlobalHotKey() {
    if let hotKeyReference {
      UnregisterEventHotKey(hotKeyReference)
      self.hotKeyReference = nil
    }
  }

  private func unregisterGlobalHotKey() {
    unregisterRegisteredGlobalHotKey()
    if let hotKeyEventHandlerReference {
      RemoveEventHandler(hotKeyEventHandlerReference)
      self.hotKeyEventHandlerReference = nil
    }
  }

  private func applyCoordinatorUpdate() {
    updatePanelContent()
    perform(coordinator.drainEffects())
  }

  private func toggleBeaconVisibility() {
    coordinator.handle(.system(.globalHotKeyPressed))
    applyCoordinatorUpdate()
  }

  // MARK: - Context Menu

  private func presentContextMenu(for panel: BeaconPanel, with event: NSEvent) {
    let menu = NSMenu(title: "")

    let settingsItem = NSMenuItem(
      title: "设置",
      action: #selector(handleSettingsFromMenu),
      keyEquivalent: ""
    )
    settingsItem.target = self

    let isVisible = coordinator.viewState.isVisible
    let hideShowItem = NSMenuItem(
      title: isVisible ? "临时隐藏" : "显示 Beacon",
      action: #selector(handleToggleVisibilityFromMenu),
      keyEquivalent: ""
    )
    hideShowItem.target = self

    let quitItem = NSMenuItem(
      title: "退出",
      action: #selector(handleQuitFromMenu),
      keyEquivalent: ""
    )
    quitItem.target = self

    menu.items = [settingsItem, hideShowItem, quitItem]

    guard let contentView = panel.contentView else {
      return
    }
    NSMenu.popUpContextMenu(menu, with: event, for: contentView)
  }

  @objc private func handleSettingsFromMenu() {
    showSettings()
  }

  private func showSettings() {
    if let settingsWindowController {
      integrationSettingsModel?.refresh()
      settingsWindowController.present()
      NSApp.activate(ignoringOtherApps: true)
      return
    }

    let integrationSettings = integrationSettingsModel ?? makeIntegrationSettingsModel()
    let rootView = BeaconSettingsView(
      size: preferences.size,
      hotKey: preferences.hotKey,
      registrationError: hotKeyRegistrationError,
      showTaskTitles: preferences.showTaskTitles,
      soundPreferences: preferences.soundPreferences,
      onSizeSelected: { [weak self] size in
        self?.updateBeaconSize(size)
      },
      onHotKeySelected: { [weak self] hotKey in
        self?.replaceGlobalHotKey(with: hotKey)
      },
      onShowTaskTitlesChanged: { [weak self] enabled in
        self?.updateShowTaskTitles(enabled)
      },
      onSoundPreferencesChanged: { [weak self] soundPreferences in
        self?.updateSoundPreferences(soundPreferences)
      },
      integrationSettings: integrationSettings
    )
    let controller = BeaconSettingsWindowController(rootView: rootView)
    settingsWindowController = controller
    controller.present()
    NSApp.activate(ignoringOtherApps: true)
  }

  private func showInitialSetup() {
    if let setupWindowController {
      setupWindowController.present()
      return
    }
    let model = InitialSetupModel(
      notificationStatus: "正在读取",
      diagnostic: .init(
        health: .repairRequired,
        summary: "正在检测 Codex Desktop",
        instructions: "仅检查本机应用与共享 App Server 的兼容性。"
      ),
      requestNotificationPermission: { completion in
        BeaconSystemIntegration.requestNotificationAuthorization(completion)
      },
      diagnose: { [weak self] completion in
        guard let self else {
          completion(Self.unavailableIntegrationDiagnostic)
          return
        }
        self.diagnoseIntegration(completion)
      },
      repair: { [weak self] completion in
        guard let self else {
          completion(Self.unavailableIntegrationDiagnostic)
          return
        }
        self.repairIntegration(completion)
      },
      complete: { [weak self] launchesAtLogin in
        self?.completeInitialSetup(launchesAtLogin: launchesAtLogin)
          ?? "Beacon 已退出，无法完成设置。"
      }
    )
    let controller = InitialSetupWindowController(rootView: InitialSetupView(model: model))
    setupWindowController = controller
    controller.present()
    model.refresh()
    model.requestNotifications()
    NSApp.activate(ignoringOtherApps: true)
  }

  private func completeInitialSetup(launchesAtLogin: Bool) -> String? {
    if let launchAtLoginError = BeaconSystemIntegration.setLaunchAtLogin(launchesAtLogin) {
      return launchAtLoginError
    }
    preferences.launchesAtLogin = launchesAtLogin
    preferences.hasCompletedInitialSetup = true
    preferencesStore.save(preferences)
    setupWindowController?.close()
    setupWindowController = nil
    startMonitoring()
    return nil
  }

  private func startMonitoring() {
    guard !hasStartedMonitoring else {
      return
    }
    hasStartedMonitoring = true
    taskMonitor?.start()
  }

  private func makeIntegrationSettingsModel() -> BeaconIntegrationSettingsModel {
    let model = BeaconIntegrationSettingsModel(
      launchesAtLogin: preferences.launchesAtLogin,
      notificationStatus: "正在读取",
      diagnostic: .init(
        health: .repairRequired,
        summary: "尚未运行诊断",
        instructions: "重新运行诊断以验证 Codex Desktop 集成。"
      ),
      setLaunchAtLogin: { enabled in
        BeaconSystemIntegration.setLaunchAtLogin(enabled)
      },
      requestNotificationPermission: { completion in
        BeaconSystemIntegration.requestNotificationAuthorization(completion)
      },
      readNotificationStatus: { completion in
        BeaconSystemIntegration.notificationAuthorizationStatus(completion)
      },
      diagnose: { [weak self] completion in
        guard let self else {
          completion(Self.unavailableIntegrationDiagnostic)
          return
        }
        self.diagnoseIntegration(completion)
      },
      repair: { [weak self] completion in
        guard let self else {
          completion(Self.unavailableIntegrationDiagnostic)
          return
        }
        self.repairIntegration(completion)
      },
      restoreDefaultIntegration: { [weak self] completion in
        guard let self else {
          completion(Self.unavailableIntegrationDiagnostic)
          return
        }
        self.restoreDefaultIntegration(completion)
      },
      persistLaunchAtLogin: { [weak self] enabled in
        guard let self else { return }
        self.preferences.launchesAtLogin = enabled
        self.preferencesStore.save(self.preferences)
      },
      exportDiagnosticLog: { [weak self] in
        self?.exportDiagnosticLog() ?? .failed("Beacon 已退出，无法导出日志。")
      }
    )
    integrationSettingsModel = model
    model.refresh()
    return model
  }

  private func exportDiagnosticLog() -> DiagnosticLogExportResult {
    let panel = NSOpenPanel()
    panel.title = "导出诊断日志"
    panel.message = "选择用于保存诊断日志副本的文件夹。"
    panel.prompt = "导出到此处"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false

    guard panel.runModal() == .OK, let directory = panel.url else {
      return .cancelled
    }

    do {
      return .exported(try diagnosticStore.export(to: directory))
    } catch {
      return .failed(error.localizedDescription)
    }
  }

  private func diagnoseIntegration(
    _ completion: @escaping @MainActor @Sendable (DesktopIntegrationDiagnostic) -> Void
  ) {
    guard let taskMonitor else {
      completion(Self.unavailableIntegrationDiagnostic)
      return
    }
    taskMonitor.diagnose(completion: completion)
  }

  private func repairIntegration(
    _ completion: @escaping @MainActor @Sendable (DesktopIntegrationDiagnostic) -> Void
  ) {
    guard let taskMonitor else {
      completion(Self.unavailableIntegrationDiagnostic)
      return
    }
    taskMonitor.repair(completion: completion)
  }

  private func restoreDefaultIntegration(
    _ completion: @escaping @MainActor @Sendable (DesktopIntegrationDiagnostic) -> Void
  ) {
    guard let taskMonitor else {
      completion(Self.unavailableIntegrationDiagnostic)
      return
    }
    taskMonitor.restoreDefaultIntegration(completion: completion)
  }

  private static let unavailableIntegrationDiagnostic = DesktopIntegrationDiagnostic(
    health: .unavailable,
    summary: "任务监测尚未初始化",
    instructions: "请重启 Beacon 后重新运行诊断。"
  )

  private func updateBeaconSize(_ size: BeaconSize) {
    guard preferences.size != size else {
      return
    }
    preferences.size = size
    preferencesStore.save(preferences)
    coordinator.handle(.user(.beaconSizeSelected(size)))
    applyCoordinatorUpdate()
  }

  private func updateShowTaskTitles(_ enabled: Bool) {
    preferences.showTaskTitles = enabled
    preferencesStore.save(preferences)
    coordinator.setShowTaskTitles(enabled)
    applyCoordinatorUpdate()
  }

  private func updateSoundPreferences(_ soundPreferences: BeaconSoundPreferences) {
    preferences.soundPreferences = soundPreferences
    preferencesStore.save(preferences)
  }

  private func replaceGlobalHotKey(with hotKey: BeaconHotKey) -> String? {
    guard preferences.hotKey != hotKey else {
      return nil
    }

    let previousHotKey = preferences.hotKey
    unregisterRegisteredGlobalHotKey()
    let status = registerGlobalHotKey(hotKey)
    guard status == noErr else {
      let restorationStatus = registerGlobalHotKey(previousHotKey)
      let message = hotKeyRegistrationFailureMessage(
        status,
        previousHotKeyRestored: restorationStatus == noErr
      )
      hotKeyRegistrationError = message
      return message
    }

    preferences.hotKey = hotKey
    preferencesStore.save(preferences)
    hotKeyRegistrationError = nil
    return nil
  }

  private func hotKeyRegistrationFailureMessage(
    _ status: OSStatus,
    previousHotKeyRestored: Bool = true
  ) -> String {
    if previousHotKeyRestored {
      "无法注册该全局快捷键（系统错误 \(status)）。已恢复原来的快捷键。"
    } else {
      "无法注册该全局快捷键（系统错误 \(status)），且原快捷键无法重新注册；已保存的设置未被更改。"
    }
  }

  @objc private func handleToggleVisibilityFromMenu() {
    toggleBeaconVisibility()
  }

  @objc private func handleQuitFromMenu() {
    NSApplication.shared.terminate(nil)
  }

  private var isCodexFrontmost = false
  private var codexFocusedScreenID: String?

  private func handleFrontmostAppChange(for app: NSRunningApplication?) {
    guard let app else {
      return
    }
    let becameFrontmost = app.bundleIdentifier == codexBundleID
    isCodexFrontmost = becameFrontmost
    if !becameFrontmost {
      codexFocusedScreenID = nil
    }
  }

  private func canAutoConfirmCompletion() -> Bool {
    guard isCodexFrontmost else {
      return false
    }
    guard let beaconScreen = panel?.screen else {
      return false
    }
    let beaconScreenID = displayIdentifier(for: beaconScreen)

    if let cachedScreenID = codexFocusedScreenID {
      return cachedScreenID == beaconScreenID
    }

    let codexApps = NSWorkspace.shared.runningApplications.filter {
      $0.bundleIdentifier == codexBundleID
    }
    guard let codexApp = codexApps.first else {
      return false
    }
    guard let codexScreenID = frontmostWindowScreenIdentifier(for: codexApp) else {
      return false
    }
    codexFocusedScreenID = codexScreenID
    return codexScreenID == beaconScreenID
  }

  private func frontmostWindowScreenIdentifier(
    for app: NSRunningApplication
  ) -> String? {
    let windowList = CGWindowListCopyWindowInfo(
      [.optionOnScreenOnly, .excludeDesktopElements],
      kCGNullWindowID
    ) as? [[CFString: Any]]

    guard let windows = windowList else {
      return nil
    }

    for window in windows {
      guard
        let ownerPID = window[kCGWindowOwnerPID] as? pid_t,
        ownerPID == app.processIdentifier,
        let layer = window[kCGWindowLayer] as? Int32,
        layer == 0
      else {
        continue
      }

      guard
        let boundsDict = window[kCGWindowBounds] as? [CFString: Any],
        let x = (boundsDict["X" as CFString] as? NSNumber)?.doubleValue,
        let y = (boundsDict["Y" as CFString] as? NSNumber)?.doubleValue,
        let width = (boundsDict["Width" as CFString] as? NSNumber)?.doubleValue,
        let height = (boundsDict["Height" as CFString] as? NSNumber)?.doubleValue
      else {
        continue
      }

      let frame = NSRect(x: x, y: y, width: width, height: height)
      for screen in NSScreen.screens {
        let intersection = screen.frame.intersection(frame)
        if intersection.width > 0, intersection.height > 0 {
          return displayIdentifier(for: screen)
        }
      }
    }

    return nil
  }

  private func activateCodex(threadID: String?) {
    let route = URL(string: "codex://threads/\(threadID ?? "new")")!
    guard let applicationURL = NSWorkspace.shared.urlForApplication(toOpen: route) else {
      NSWorkspace.shared.open(route)
      return
    }
    let configuration = NSWorkspace.OpenConfiguration()
    let deepLinkThreadID = threadID
    NSWorkspace.shared.openApplication(
      at: applicationURL,
      configuration: configuration
    ) { _, error in
      guard error == nil else {
        return
      }
      if let threadID = deepLinkThreadID {
        let deepLink = URL(string: "codex://threads/\(threadID)")!
        NSWorkspace.shared.open(deepLink)
      } else {
        NSWorkspace.shared.open(route)
      }
    }
  }

  private func displayIdentifier(for screen: NSScreen) -> String {
    let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
    return screenNumber?.stringValue ?? "primary"
  }

  private func safeFrame(for screen: NSScreen) -> NSRect {
    let visibleFrame = screen.visibleFrame
    let screenFrame = screen.frame
    let insets = screen.safeAreaInsets
    let minX = max(visibleFrame.minX, screenFrame.minX + insets.left)
    let maxX = min(visibleFrame.maxX, screenFrame.maxX - insets.right)
    let minY = max(visibleFrame.minY, screenFrame.minY + insets.bottom)
    let maxY = min(visibleFrame.maxY, screenFrame.maxY - insets.top)
    return NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
  }

  private func beaconRect(from frame: NSRect) -> BeaconRect {
    BeaconRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height)
  }
}

private extension BeaconStatus {
  var traceName: String {
    switch self {
    case .idle: "idle"
    case .working: "working"
    case .waitingForYou: "waiting_for_you"
    case .completed: "completed"
    case .monitoringUnavailable: "monitoring_unavailable"
    }
  }
}

private extension BeaconLightIllumination {
  var traceName: String {
    switch self {
    case .off: "off"
    case .steady: "steady"
    case .breathing: "breathing"
    case .flashing: "flashing"
    }
  }
}

private extension TaskEvent {
  var traceDescription: String {
    switch self {
    case .monitoringConnectionEstablished(let protocolCompatible):
      "monitoring_connection_established(protocol_compatible=\(protocolCompatible))"
    case .monitoringRuntimeValidated:
      "monitoring_runtime_validated"
    case .monitoringConnectionFailed:
      "monitoring_connection_failed"
    case .monitoringObservationBecameStale:
      "monitoring_observation_became_stale"
    case .monitoringSnapshotRequested:
      "monitoring_snapshot_requested"
    case .quotaSnapshotRequested:
      "quota_snapshot_requested"
    case .appServerMessage:
      "app_server_message"
    }
  }
}
