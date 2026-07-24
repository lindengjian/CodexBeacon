import AppKit
import CoreGraphics
import Foundation

struct ProbeResult: Codable {
    let appKitLevel: Int
    let cgWindowLayer: Int?
    let collectionBehaviorRawValue: UInt
    let canJoinAllApplications: Bool
    let canJoinAllSpaces: Bool
    let fullScreenAuxiliary: Bool
    let isFloatingPanel: Bool
    let windowNumber: Int
}

final class ProbeDelegate: NSObject, NSApplicationDelegate {
    private var panel: NSPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = NSPanel(
            contentRect: NSRect(x: 80, y: 80, width: 180, height: 70),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.title = "Codex Beacon Window Level Probe"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .canJoinAllApplications,
            .fullScreenAuxiliary,
            .stationary,
        ]
        panel.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.85)
        panel.isOpaque = false
        panel.hasShadow = true

        let label = NSTextField(labelWithString: "Codex Beacon\nlevel probe")
        label.alignment = .center
        label.textColor = .black
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.frame = NSRect(x: 10, y: 14, width: 160, height: 42)
        panel.contentView?.addSubview(label)

        panel.orderFrontRegardless()
        self.panel = panel

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.reportAndExit(panel)
        }
    }

    private func reportAndExit(_ panel: NSPanel) {
        let windowNumber = panel.windowNumber
        let windows = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []

        let matchingWindow = windows.first {
            ($0[kCGWindowNumber as String] as? Int) == windowNumber
        }
        let cgLayer = matchingWindow?[kCGWindowLayer as String] as? Int
        let behavior = panel.collectionBehavior
        let result = ProbeResult(
            appKitLevel: panel.level.rawValue,
            cgWindowLayer: cgLayer,
            collectionBehaviorRawValue: behavior.rawValue,
            canJoinAllApplications: behavior.contains(.canJoinAllApplications),
            canJoinAllSpaces: behavior.contains(.canJoinAllSpaces),
            fullScreenAuxiliary: behavior.contains(.fullScreenAuxiliary),
            isFloatingPanel: panel.isFloatingPanel,
            windowNumber: windowNumber
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(result) {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }

        panel.orderOut(nil)
        NSApplication.shared.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = ProbeDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
