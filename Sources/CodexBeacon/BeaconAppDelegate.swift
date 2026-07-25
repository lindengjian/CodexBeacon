import AppKit
import CodexBeaconCore
import SwiftUI

@MainActor
final class BeaconAppDelegate: NSObject, NSApplicationDelegate {
  private let coordinator = AppCoordinator()
  private var panel: BeaconPanel?
  private var taskMonitor: DesktopAppServerMonitor?

  func applicationDidFinishLaunching(_ notification: Notification) {
    coordinator.start()
    present(coordinator.viewState)
    perform(coordinator.drainEffects())
    taskMonitor = DesktopAppServerMonitor(
      deliver: { [weak self] event in self?.handleTaskEvent(event) },
      requestsProvider: { [weak self] in self?.coordinator.drainAppServerRequests() ?? [] }
    )
    taskMonitor?.start()
  }

  private func handleTaskEvent(_ event: TaskEvent) {
    coordinator.handle(.time(.advanced(to: Date())))
    coordinator.handle(.task(event))
    updatePanelContent()
  }

  private func present(_ state: BeaconViewState) {
    let panel = BeaconPanel(
      state: state,
      onActivate: { [weak self] in self?.handleBeaconActivation() }
    )
    self.panel = panel
    position(panel)
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
      }
    }
  }

  private func handleBeaconActivation() {
    coordinator.handle(.user(.beaconActivated))
    updatePanelContent()
    perform(coordinator.drainEffects())
  }

  private func updatePanelContent() {
    panel?.contentView = NSHostingView(
      rootView: IdleBeaconView(
        state: coordinator.viewState,
        onActivate: { [weak self] in self?.handleBeaconActivation() }
      )
    )
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

  private func position(_ panel: NSPanel) {
    guard let visibleFrame = NSScreen.main?.visibleFrame else {
      panel.center()
      return
    }

    let origin = NSPoint(
      x: visibleFrame.maxX - panel.frame.width - 24,
      y: visibleFrame.midY - panel.frame.height / 2
    )
    panel.setFrameOrigin(origin)
  }
}
