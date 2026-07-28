import AppKit
import Testing

@testable import CodexBeacon
@testable import CodexBeaconCore

@MainActor
struct BeaconPanelDragTests {
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
