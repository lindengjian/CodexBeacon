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
    coordinator.handle(.task(event))
    panel?.contentView = NSHostingView(rootView: IdleBeaconView(state: coordinator.viewState))
  }

  private func present(_ state: BeaconViewState) {
    let panel = BeaconPanel(state: state)
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
      }
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
