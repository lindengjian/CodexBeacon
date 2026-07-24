import AppKit
import CodexBeaconCore
import SwiftUI

@MainActor
final class BeaconAppDelegate: NSObject, NSApplicationDelegate {
  private let coordinator = AppCoordinator()
  private var panel: BeaconPanel?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApplication.shared.setActivationPolicy(.accessory)

    coordinator.start()
    present(coordinator.viewState)
    perform(coordinator.drainEffects())
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
