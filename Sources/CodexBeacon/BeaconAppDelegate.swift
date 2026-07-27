import AppKit
import Carbon
import CodexBeaconCore
import SwiftUI

@MainActor
final class BeaconAppDelegate: NSObject, NSApplicationDelegate {
  private lazy var coordinator = AppCoordinator(
    requiresSharedRuntimeEvidence: true,
    initialBeaconAnchor: BeaconPlacementStore.load()
  )
  private var panel: BeaconPanel?
  private var taskMonitor: DesktopAppServerMonitor?
  private var screenParametersObserver: NSObjectProtocol?
  private var frontmostAppObserver: NSObjectProtocol?
  private var codexBundleID = "com.anthropic.codex"
  private var hotKeyReference: EventHotKeyRef?
  private var hotKeyEventHandlerReference: EventHandlerRef?

  func applicationDidFinishLaunching(_ notification: Notification) {
    coordinator.start()
    coordinator.autoConfirmCondition = { [weak self] in
      self?.canAutoConfirmCompletion() ?? false
    }
    present(coordinator.viewState)
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
    taskMonitor = DesktopAppServerMonitor(
      deliver: { [weak self] event in self?.handleTaskEvent(event) },
      requestsProvider: { [weak self] in self?.coordinator.drainAppServerRequests() ?? [] }
    )
    taskMonitor?.start()
    registerGlobalHotKey()
  }

  func applicationWillTerminate(_ notification: Notification) {
    if let screenParametersObserver {
      NotificationCenter.default.removeObserver(screenParametersObserver)
    }
    if let frontmostAppObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(frontmostAppObserver)
    }
    unregisterGlobalHotKey()
  }

  private func handleTaskEvent(_ event: TaskEvent) {
    coordinator.handle(.time(.advanced(to: Date())))
    coordinator.handle(.task(event))
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
        BeaconPlacementStore.save(placement.anchor)
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
    panel?.update(state: coordinator.viewState)
  }

  // MARK: - Global Hotkey

  private func registerGlobalHotKey() {
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

    let hotKeyID = EventHotKeyID(signature: 0x4344_424B, id: 1)  // 'CDBK'
    let status = RegisterEventHotKey(
      UInt32(kVK_ANSI_C),
      UInt32(controlKey | optionKey | cmdKey),
      hotKeyID,
      GetApplicationEventTarget(),
      0,
      &hotKeyReference
    )

    if status != noErr {
      hotKeyReference = nil
    }
  }

  private func unregisterGlobalHotKey() {
    if let hotKeyReference {
      UnregisterEventHotKey(hotKeyReference)
      self.hotKeyReference = nil
    }
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
    let toggledVisibility = !coordinator.viewState.isVisible
    coordinator.handle(.system(.visibilityChanged(toggledVisibility)))
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
    // Acceptance criteria #5: opening settings does not change
    // current task or quota state.
    NSApp.activate(ignoringOtherApps: true)
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

private enum BeaconPlacementStore {
  private static let key = "beaconPlacementAnchor"

  static func load() -> BeaconAnchor? {
    guard let data = UserDefaults.standard.data(forKey: key) else {
      return nil
    }
    return try? JSONDecoder().decode(BeaconAnchor.self, from: data)
  }

  static func save(_ anchor: BeaconAnchor) {
    guard let data = try? JSONEncoder().encode(anchor) else {
      return
    }
    UserDefaults.standard.set(data, forKey: key)
  }
}
