import AppKit
import CodexBeaconCore
import SwiftUI

@MainActor
final class BeaconViewStateStore: ObservableObject {
  @Published var state: BeaconViewState

  init(state: BeaconViewState) {
    self.state = state
  }
}

@MainActor
final class BeaconPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }

  private let onDragEnded: () -> Void
  private let stateStore: BeaconViewStateStore

  init(
    state: BeaconViewState,
    onActivate: @escaping () -> Void,
    onDragEnded: @escaping () -> Void
  ) {
    self.onDragEnded = onDragEnded
    stateStore = BeaconViewStateStore(state: state)
    let dimensions = state.dimensions
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
    collectionBehavior = [
      .canJoinAllSpaces,
      .canJoinAllApplications,
      .stationary,
    ]
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
      rootView: IdleBeaconView(stateStore: stateStore, onActivate: onActivate)
    )
  }

  override func mouseUp(with event: NSEvent) {
    super.mouseUp(with: event)
    onDragEnded()
  }

  func apply(_ placement: BeaconPlacement) {
    let frame = NSRect(
      x: placement.frame.x,
      y: placement.frame.y,
      width: placement.frame.width,
      height: placement.frame.height
    )
    setFrame(frame, display: true)
  }

  func update(state: BeaconViewState) {
    stateStore.state = state
  }
}
