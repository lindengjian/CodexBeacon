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
  private var frameBeforePointerDown: NSRect?
  var onRightClick: ((NSEvent) -> Void)?

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

  override func rightMouseDown(with event: NSEvent) {
    onRightClick?(event)
  }

  override func sendEvent(_ event: NSEvent) {
    switch event.type {
    case .leftMouseDown:
      frameBeforePointerDown = frame
      super.sendEvent(event)
    case .leftMouseUp:
      let frameBeforeDrag = frameBeforePointerDown
      frameBeforePointerDown = nil
      super.sendEvent(event)
      if let frameBeforeDrag, frameBeforeDrag.origin != frame.origin {
        onDragEnded()
      }
    default:
      super.sendEvent(event)
    }
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

  // MARK: - Border pulse

  /// Triggers a 5-second border pulse animation using the reset accent colour.
  /// Safe to call when a pulse is already active — the new animation replaces
  /// the current one.
  func startBorderPulse() {
    guard let contentView else { return }

    contentView.wantsLayer = true
    contentView.layer?.cornerRadius = 30
    contentView.layer?.masksToBounds = true

    // Remove any in-flight border animation.
    contentView.layer?.removeAnimation(forKey: "resetBorderPulse")

    let pulseColor = CGColor(red: 0.17, green: 0.82, blue: 0.36, alpha: 1.0)

    let borderAnimation = CAKeyframeAnimation(keyPath: "borderWidth")
    borderAnimation.values = [0, 3, 3, 0, 0]
    borderAnimation.keyTimes = [0, 0.1, 0.8, 0.9, 1.0]
    borderAnimation.duration = 5
    borderAnimation.isRemovedOnCompletion = true
    borderAnimation.fillMode = .forwards

    let colorAnimation = CAKeyframeAnimation(keyPath: "borderColor")
    colorAnimation.values = [
      CGColor.clear,
      pulseColor,
      pulseColor,
      pulseColor.copy(alpha: 0.3) as Any,
      CGColor.clear,
    ]
    colorAnimation.keyTimes = [0, 0.1, 0.7, 0.9, 1.0]
    colorAnimation.duration = 5
    colorAnimation.isRemovedOnCompletion = true
    colorAnimation.fillMode = .forwards

    let group = CAAnimationGroup()
    group.animations = [borderAnimation, colorAnimation]
    group.duration = 5
    group.isRemovedOnCompletion = true
    group.fillMode = .forwards

    contentView.layer?.borderWidth = 0
    contentView.layer?.borderColor = CGColor.clear
    contentView.layer?.add(group, forKey: "resetBorderPulse")
  }
}
