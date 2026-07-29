import AppKit
import CoreImage
import SwiftUI
import Testing

@testable import CodexBeacon
@testable import CodexBeaconCore

@MainActor
struct BeaconPanelDragTests {
  @Test("Beacon panel uses behind-window visual effect backing for translucent glass")
  func beaconPanelUsesBehindWindowVisualEffectBacking() {
    _ = NSApplication.shared
    let panel = BeaconPanel(state: .idle, onActivate: {}, onDragEnded: {})
    defer { panel.close() }
    panel.updateAppearance(.dark, systemScheme: .light)

    #expect(!panel.hasShadow)
    let visualEffectView = panel.contentView?.subviews.compactMap { $0 as? NSVisualEffectView }.first
    #expect(visualEffectView != nil)
    #expect(visualEffectView?.blendingMode == .behindWindow)
    #expect(visualEffectView?.material == .popover)
    #expect(visualEffectView?.state == .active)
    #expect(visualEffectView?.alphaValue == CGFloat(BeaconGlassStyle.visualEffectAlpha))
    #expect(visualEffectView?.appearance?.name == .vibrantDark)
    #expect(visualEffectView?.maskImage != nil)
    let blurFilter = visualEffectView?.layer?.backgroundFilters?.compactMap { $0 as? CIFilter }
      .first { $0.name == "CIGaussianBlur" }
    #expect(blurFilter?.value(forKey: kCIInputRadiusKey) as? Double == BeaconGlassStyle.backgroundBlurRadius)
    #expect(visualEffectView?.subviews.isEmpty == true)
    #expect(panel.contentView?.subviews.contains { $0 is NSHostingView<IdleBeaconView> } == true)
    #expect(!(panel.contentView is NSVisualEffectView))
  }

  @Test("Beacon glass blurs the backdrop without raw window alpha passthrough")
  func beaconGlassBlursBackdropWithoutRawWindowAlphaPassthrough() {
    #expect(BeaconGlassStyle.visualEffectAlpha == 1.0)
    #expect(BeaconGlassStyle.backgroundBlurRadius == 12.0)
    #expect(BeaconGlassStyle.surfaceTintOpacity == 0.18)
  }

  @Test("Beacon glass updates for explicit and system-resolved appearances")
  func beaconGlassUpdatesForAppearance() {
    _ = NSApplication.shared
    let panel = BeaconPanel(state: .idle, onActivate: {}, onDragEnded: {})
    defer { panel.close() }

    panel.updateAppearance(.light, systemScheme: .dark)
    let visualEffectView = panel.contentView?.subviews.compactMap { $0 as? NSVisualEffectView }.first
    #expect(visualEffectView?.appearance?.name == .vibrantLight)

    panel.updateAppearance(.system, systemScheme: .dark)
    #expect(visualEffectView?.appearance?.name == .vibrantDark)
  }

  @Test("visually unchanged Beacon state does not republish the SwiftUI panel")
  func panelSkipsVisuallyUnchangedState() {
    _ = NSApplication.shared
    let panel = BeaconPanel(state: .idle, onActivate: {}, onDragEnded: {})
    defer { panel.close() }

    var timestampOnlyChange = BeaconViewState.idle
    timestampOnlyChange.lastUpdatedAt = Date()

    #expect(panel.update(state: timestampOnlyChange) == false)

    var visibleChange = timestampOnlyChange
    visibleChange.quotaTrack = .init(style: .gauge, fillFraction: 0.5)

    #expect(panel.update(state: visibleChange) == true)
  }

  @Test("releasing a dragged Beacon notifies the placement coordinator")
  func releasingBeaconNotifiesPlacementCoordinator() {
    _ = NSApplication.shared
    var dragEndCount = 0
    let panel = BeaconPanel(
      state: .idle,
      onActivate: {},
      onDragEnded: { dragEndCount += 1 }
    )
    defer { panel.close() }

    guard let press = NSEvent.mouseEvent(
      with: .leftMouseDown,
      location: .init(x: 20, y: 20),
      modifierFlags: [],
      timestamp: 0,
      windowNumber: panel.windowNumber,
      context: nil,
      eventNumber: 0,
      clickCount: 1,
      pressure: 1
    ), let release = NSEvent.mouseEvent(
      with: .leftMouseUp,
      location: .init(x: 20, y: 20),
      modifierFlags: [],
      timestamp: 0,
      windowNumber: panel.windowNumber,
      context: nil,
      eventNumber: 0,
      clickCount: 1,
      pressure: 0
    ) else {
      Issue.record("Failed to construct Beacon drag release")
      return
    }

    panel.sendEvent(press)
    panel.setFrameOrigin(.init(x: panel.frame.minX + 20, y: panel.frame.minY))
    panel.sendEvent(release)

    #expect(dragEndCount == 1)
  }

  @Test("reduce motion suppresses a new reset pulse and removes an active one")
  func reduceMotionControlsBorderPulse() {
    _ = NSApplication.shared
    let panel = BeaconPanel(state: .idle, onActivate: {}, onDragEnded: {})
    defer { panel.close() }

    panel.updateBorderPulse(isActive: true, reducesMotion: false)
    #expect(panel.contentView?.layer?.animation(forKey: "resetBorderPulse") != nil)

    panel.updateBorderPulse(isActive: true, reducesMotion: true)
    #expect(panel.contentView?.layer?.animation(forKey: "resetBorderPulse") == nil)

    panel.updateBorderPulse(isActive: true, reducesMotion: true)
    #expect(panel.contentView?.layer?.animation(forKey: "resetBorderPulse") == nil)
  }
}
