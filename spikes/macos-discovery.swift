import AppKit
import CoreGraphics
import Foundation

struct RunningAppSummary: Codable {
    let name: String
    let bundleIdentifier: String?
    let bundleURL: String?
    let processIdentifier: Int32
}

struct WindowSummary: Codable {
    let ownerName: String
    let ownerPID: Int
    let name: String?
    let layer: Int
    let alpha: Double
    let bounds: [String: Int]
}

struct DiscoveryResult: Codable {
    let codexURLHandler: String?
    let frontmostApplication: RunningAppSummary?
    let matchingApplications: [RunningAppSummary]
    let matchingWindows: [WindowSummary]
}

let workspace = NSWorkspace.shared
let codexURL = URL(string: "codex://threads/new")!
let handlerURL = workspace.urlForApplication(toOpen: codexURL)

let matchingApplications = workspace.runningApplications.compactMap { app -> RunningAppSummary? in
    let searchable = [
        app.localizedName,
        app.bundleIdentifier,
        app.bundleURL?.path,
    ]
    .compactMap { $0 }
    .joined(separator: " ")
    .lowercased()

    guard searchable.contains("codex") || searchable.contains("chatgpt") else {
        return nil
    }

    return RunningAppSummary(
        name: app.localizedName ?? "(unknown)",
        bundleIdentifier: app.bundleIdentifier,
        bundleURL: app.bundleURL?.path,
        processIdentifier: app.processIdentifier
    )
}

let windowInfo = CGWindowListCopyWindowInfo(
    [.optionOnScreenOnly, .excludeDesktopElements],
    kCGNullWindowID
) as? [[String: Any]] ?? []

let matchingWindows = windowInfo.compactMap { info -> WindowSummary? in
    let ownerName = info[kCGWindowOwnerName as String] as? String ?? "(unknown)"
    let ownerPID = info[kCGWindowOwnerPID as String] as? Int ?? -1
    let isMatchingPID = matchingApplications.contains {
        Int($0.processIdentifier) == ownerPID
    }
    let normalizedOwner = ownerName.lowercased()

    guard isMatchingPID || normalizedOwner.contains("codex") || normalizedOwner.contains("chatgpt") else {
        return nil
    }

    let rawBounds = info[kCGWindowBounds as String] as? [String: Any] ?? [:]
    let bounds = rawBounds.compactMapValues { value -> Int? in
        if let number = value as? NSNumber {
            return number.intValue
        }
        return nil
    }

    return WindowSummary(
        ownerName: ownerName,
        ownerPID: ownerPID,
        name: info[kCGWindowName as String] as? String,
        layer: info[kCGWindowLayer as String] as? Int ?? -1,
        alpha: info[kCGWindowAlpha as String] as? Double ?? -1,
        bounds: bounds
    )
}

let result = DiscoveryResult(
    codexURLHandler: handlerURL?.path,
    frontmostApplication: workspace.frontmostApplication.map {
        RunningAppSummary(
            name: $0.localizedName ?? "(unknown)",
            bundleIdentifier: $0.bundleIdentifier,
            bundleURL: $0.bundleURL?.path,
            processIdentifier: $0.processIdentifier
        )
    },
    matchingApplications: matchingApplications,
    matchingWindows: matchingWindows
)

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
let data = try encoder.encode(result)
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data("\n".utf8))
