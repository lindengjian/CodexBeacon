import Foundation

/// Pure render-state for a single Beacon lamp, decoupled from SwiftUI so the
/// model can be unit-tested without rendering a view.
///
/// A light is one of four illumination modes:
/// - `off`: static, dim.
/// - `steady`: static, fully lit.
/// - `breathing`: slow opacity oscillation while lit.
/// - `flashing`: faster, more explicit opacity oscillation while lit.
///
/// When the user has macOS Reduce Motion enabled, every animated mode
/// collapses to its static counterpart, with one exception: a flashing
/// (waiting) green light is replaced with a static "double ring" outline so
/// it is still distinguishable from a solid green completion light.
public struct LightRenderLogic: Equatable, Sendable {
  public let illumination: BeaconLightIllumination
  public let reducesMotion: Bool

  public init(illumination: BeaconLightIllumination, reducesMotion: Bool) {
    self.illumination = illumination
    self.reducesMotion = reducesMotion
  }

  public var shouldAnimate: Bool {
    !reducesMotion && (illumination == .breathing || illumination == .flashing)
  }

  public var showsWaitingRing: Bool {
    reducesMotion && illumination == .flashing
  }

  /// Static opacity for non-animated states.
  public var baseOpacity: Double {
    switch illumination {
    case .off: 0.08
    case .steady, .breathing, .flashing: 1.0
    }
  }

  /// Lowest opacity the light dips to during an animation cycle.
  public var minimumOpacity: Double {
    switch illumination {
    case .flashing: 0.4
    case .breathing: 0.6
    case .steady, .off: 1.0
    }
  }

  /// Full animation period (one up + one down) in seconds. Derived from the
  /// `easeInOut(duration:).repeatForever(autoreverses: true)` shape that
  /// used to be applied imperatively to the view's @State phase.
  public var animationPeriod: Double {
    illumination == .flashing ? 1.4 : 3.6
  }

  /// Opacity to render at the given instant. Pure function of `illumination`,
  /// `reducesMotion`, and the wall clock — no SwiftUI state involved.
  ///
  /// - When `shouldAnimate` is false, returns `baseOpacity` directly. This
  ///   is the load-bearing contract that the bug depended on: switching
  ///   out of an animated mode must immediately collapse to the static
  ///   opacity, regardless of any leftover animation schedule.
  /// - When `shouldAnimate` is true, returns a smooth oscillation between
  ///   `minimumOpacity` and 1.0 with `animationPeriod`. The
  ///   `(1 - cos(...)) / 2` shape is used so the function actually reaches
  ///   the endpoints (1.0 and `minimumOpacity`) at the cycle boundaries,
  ///   unlike a raw sine which only approximates them.
  public func displayedOpacity(at date: Date) -> Double {
    guard shouldAnimate else { return baseOpacity }
    let phase = (1 - cos(date.timeIntervalSinceReferenceDate * 2 * .pi / animationPeriod)) / 2
    return minimumOpacity + (1.0 - minimumOpacity) * phase
  }
}
