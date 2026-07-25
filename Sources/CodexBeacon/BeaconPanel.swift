import AppKit
import CodexBeaconCore
import SwiftUI

@MainActor
final class BeaconPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }

  init(state: BeaconViewState, onActivate: @escaping () -> Void) {
    let dimensions = state.size.dimensions
    let contentRect = NSRect(
      x: 0,
      y: 0,
      width: dimensions.width,
      height: dimensions.height
    )

    super.init(
      contentRect: contentRect,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )

    level = .floating
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    isFloatingPanel = true
    hidesOnDeactivate = false
    becomesKeyOnlyIfNeeded = true
    isMovableByWindowBackground = true
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    isReleasedWhenClosed = false
    animationBehavior = .none
    contentView = NSHostingView(
      rootView: IdleBeaconView(state: state, onActivate: onActivate)
    )
  }
}
