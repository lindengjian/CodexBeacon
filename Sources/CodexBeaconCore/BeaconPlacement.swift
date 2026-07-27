import Foundation

public enum BeaconOrientation: Equatable, Sendable {
  case vertical
  case horizontal
}

public enum BeaconEdge: String, Codable, Equatable, Sendable {
  case left
  case right
  case top
  case bottom

  var orientation: BeaconOrientation {
    switch self {
    case .left, .right:
      .vertical
    case .top, .bottom:
      .horizontal
    }
  }
}

public struct BeaconRect: Equatable, Sendable {
  public let x: Double
  public let y: Double
  public let width: Double
  public let height: Double

  public init(x: Double, y: Double, width: Double, height: Double) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }

  var maxX: Double { x + width }
  var maxY: Double { y + height }
}

public struct BeaconDisplay: Equatable, Sendable {
  public let identifier: String
  /// The display area supplied by AppKit after excluding the menu bar, notch,
  /// and any currently visible Dock.
  public let safeFrame: BeaconRect

  public init(identifier: String, safeFrame: BeaconRect) {
    self.identifier = identifier
    self.safeFrame = safeFrame
  }
}

public struct BeaconDisplayLayout: Equatable, Sendable {
  public let primaryDisplayIdentifier: String
  public let displays: [BeaconDisplay]

  public init(primaryDisplayIdentifier: String, displays: [BeaconDisplay]) {
    self.primaryDisplayIdentifier = primaryDisplayIdentifier
    self.displays = displays
  }

  func display(identifier: String) -> BeaconDisplay? {
    displays.first { $0.identifier == identifier }
  }
}

public struct BeaconAnchor: Codable, Equatable, Sendable {
  public let displayIdentifier: String
  public let edge: BeaconEdge
  /// Point offset from the safe area's lower or left edge, never a desktop coordinate.
  public let alongEdgeOffset: Double

  public init(displayIdentifier: String, edge: BeaconEdge, alongEdgeOffset: Double) {
    self.displayIdentifier = displayIdentifier
    self.edge = edge
    self.alongEdgeOffset = alongEdgeOffset
  }
}

public struct BeaconPlacement: Equatable, Sendable {
  public let anchor: BeaconAnchor
  public let frame: BeaconRect

  public init(anchor: BeaconAnchor, frame: BeaconRect) {
    self.anchor = anchor
    self.frame = frame
  }
}

struct BeaconPlacementResolver {
  static func defaultAnchor(in display: BeaconDisplay) -> BeaconAnchor {
    let dimensions = BeaconSize.standard.dimensions(for: .vertical)
    return BeaconAnchor(
      displayIdentifier: display.identifier,
      edge: .right,
      alongEdgeOffset: (display.safeFrame.height - dimensions.height) / 2
    )
  }

  static func anchor(
    forDraggedFrame frame: BeaconRect,
    on display: BeaconDisplay
  ) -> BeaconAnchor {
    let safeFrame = display.safeFrame
    let distances: [(BeaconEdge, Double)] = [
      (.left, abs(frame.x - safeFrame.x)),
      (.right, abs(safeFrame.maxX - frame.maxX)),
      (.bottom, abs(frame.y - safeFrame.y)),
      (.top, abs(safeFrame.maxY - frame.maxY)),
    ]
    let edge = distances.min { $0.1 < $1.1 }!.0
    let offset = switch edge {
    case .left, .right:
      frame.y - safeFrame.y
    case .top, .bottom:
      frame.x - safeFrame.x
    }

    return BeaconAnchor(
      displayIdentifier: display.identifier,
      edge: edge,
      alongEdgeOffset: offset
    )
  }

  static func placement(
    for anchor: BeaconAnchor,
    on display: BeaconDisplay
  ) -> BeaconPlacement {
    let orientation = anchor.edge.orientation
    let dimensions = BeaconSize.standard.dimensions(for: orientation)
    let safeFrame = display.safeFrame
    let frame: BeaconRect

    switch anchor.edge {
    case .left:
      frame = .init(
        x: safeFrame.x,
        y: safeFrame.y + clamped(anchor.alongEdgeOffset, maximum: safeFrame.height - dimensions.height),
        width: dimensions.width,
        height: dimensions.height
      )
    case .right:
      frame = .init(
        x: safeFrame.maxX - dimensions.width,
        y: safeFrame.y + clamped(anchor.alongEdgeOffset, maximum: safeFrame.height - dimensions.height),
        width: dimensions.width,
        height: dimensions.height
      )
    case .bottom:
      frame = .init(
        x: safeFrame.x + clamped(anchor.alongEdgeOffset, maximum: safeFrame.width - dimensions.width),
        y: safeFrame.y,
        width: dimensions.width,
        height: dimensions.height
      )
    case .top:
      frame = .init(
        x: safeFrame.x + clamped(anchor.alongEdgeOffset, maximum: safeFrame.width - dimensions.width),
        y: safeFrame.maxY - dimensions.height,
        width: dimensions.width,
        height: dimensions.height
      )
    }

    let clampedAnchor = BeaconAnchor(
      displayIdentifier: display.identifier,
      edge: anchor.edge,
      alongEdgeOffset: anchor.edge.orientation == .vertical
        ? frame.y - safeFrame.y
        : frame.x - safeFrame.x
    )
    return BeaconPlacement(anchor: clampedAnchor, frame: frame)
  }

  private static func clamped(_ value: Double, maximum: Double) -> Double {
    min(max(value, 0), max(maximum, 0))
  }
}
