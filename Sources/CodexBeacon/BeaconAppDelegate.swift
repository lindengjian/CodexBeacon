import AppKit
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

  func applicationDidFinishLaunching(_ notification: Notification) {
    coordinator.start()
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
    taskMonitor = DesktopAppServerMonitor(
      deliver: { [weak self] event in self?.handleTaskEvent(event) },
      requestsProvider: { [weak self] in self?.coordinator.drainAppServerRequests() ?? [] }
    )
    taskMonitor?.start()
  }

  func applicationWillTerminate(_ notification: Notification) {
    if let screenParametersObserver {
      NotificationCenter.default.removeObserver(screenParametersObserver)
    }
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
    updatePanelContent()
    perform(coordinator.drainEffects())
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
    updatePanelContent()
    perform(coordinator.drainEffects())
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
    updatePanelContent()
    perform(coordinator.drainEffects())
  }

  private func updatePanelContent() {
    panel?.update(state: coordinator.viewState)
  }

  private func activateCodex(threadID: String?) {
    let route = URL(string: "codex://threads/\(threadID ?? "new")")!
    guard let applicationURL = NSWorkspace.shared.urlForApplication(toOpen: route) else {
      NSWorkspace.shared.open(route)
      return
    }
    NSWorkspace.shared.openApplication(
      at: applicationURL,
      configuration: .init()
    ) { _, _ in
      NSWorkspace.shared.open(route)
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
