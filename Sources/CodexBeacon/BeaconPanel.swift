import AppKit
import CodexBeaconCore
import CoreImage
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
    hasShadow = false
    isReleasedWhenClosed = false
    animationBehavior = .none

    let rootView = NSView(frame: contentRect)
    rootView.wantsLayer = true
    rootView.layer?.backgroundColor = NSColor.clear.cgColor

    let glassView = NSVisualEffectView(frame: contentRect)
    glassView.blendingMode = .behindWindow
    glassView.material = .popover
    glassView.appearance = NSAppearance(named: .vibrantDark)
    glassView.state = .active
    glassView.alphaValue = BeaconGlassStyle.visualEffectAlpha
    glassView.autoresizingMask = [.width, .height]
    glassView.wantsLayer = true
    applyGlassMask(to: glassView, size: contentRect.size, surface: state.surface)

    let hostingView = NSHostingView(
      rootView: IdleBeaconView(stateStore: stateStore, onActivate: onActivate)
    )
    hostingView.frame = glassView.bounds
    hostingView.autoresizingMask = [.width, .height]
    hostingView.wantsLayer = true
    hostingView.layer?.backgroundColor = NSColor.clear.cgColor
    rootView.addSubview(glassView)
    rootView.addSubview(hostingView)
    contentView = rootView
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
    if let glassView = glassView {
      applyGlassMask(to: glassView, size: frame.size, surface: stateStore.state.surface)
    }
  }

  @discardableResult
  func update(state: BeaconViewState) -> Bool {
    let previous = stateStore.state
    guard !previous.hasSameVisibleContent(as: state) else {
      return false
    }
    stateStore.state = state
    if let glassView = glassView,
      previous.dimensions != state.dimensions || previous.surface != state.surface
    {
      let size = NSSize(width: state.dimensions.width, height: state.dimensions.height)
      applyGlassMask(to: glassView, size: size, surface: state.surface)
    }
    return true
  }

  // MARK: - Border pulse

  /// Triggers a 5-second border pulse animation using the reset accent colour.
  /// Safe to call when a pulse is already active — the new animation replaces
  /// the current one.
  func startBorderPulse() {
    guard let contentView else { return }

    contentView.wantsLayer = true
    contentView.layer?.cornerRadius = glassCornerRadius(
      for: stateStore.state.surface,
      size: contentView.bounds.size
    )
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

  /// Applies reset attention while respecting the current macOS accessibility
  /// setting. Calling this for a Reduce Motion update also removes any pulse
  /// that was already in flight.
  func updateBorderPulse(isActive: Bool, reducesMotion: Bool) {
    guard isActive, !reducesMotion else {
      stopBorderPulse()
      return
    }
    startBorderPulse()
  }

  /// Immediately removes the reset attention animation when macOS Reduce
  /// Motion is enabled while a pulse is already running.
  func stopBorderPulse() {
    guard let layer = contentView?.layer else { return }
    layer.removeAnimation(forKey: "resetBorderPulse")
    layer.borderWidth = 0
    layer.borderColor = CGColor.clear
  }

  private var glassView: NSVisualEffectView? {
    contentView?.subviews.compactMap { $0 as? NSVisualEffectView }.first
  }

  private func applyGlassMask(
    to glassView: NSVisualEffectView,
    size: NSSize,
    surface: BeaconSurfaceState
  ) {
    let cornerRadius = glassCornerRadius(for: surface, size: size)
    glassView.layer?.cornerRadius = cornerRadius
    glassView.layer?.masksToBounds = true
    glassView.layer?.backgroundFilters = [Self.gaussianBlurFilter()]
    glassView.maskImage = Self.roundedMaskImage(size: size, cornerRadius: cornerRadius)
  }

  private func glassCornerRadius(for surface: BeaconSurfaceState, size: NSSize) -> CGFloat {
    let requested = switch surface.shape {
    case .roundedRectangle(let cornerRadius):
      CGFloat(cornerRadius)
    }
    return min(requested, min(size.width, size.height) / 2)
  }

  private static func roundedMaskImage(size: NSSize, cornerRadius: CGFloat) -> NSImage {
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.white.setFill()
    NSBezierPath(
      roundedRect: NSRect(origin: .zero, size: size),
      xRadius: cornerRadius,
      yRadius: cornerRadius
    ).fill()
    image.unlockFocus()
    return image
  }

  private static func gaussianBlurFilter() -> CIFilter {
    let filter = CIFilter(name: "CIGaussianBlur") ?? CIFilter()
    filter.setValue(BeaconGlassStyle.backgroundBlurRadius, forKey: kCIInputRadiusKey)
    return filter
  }
}
