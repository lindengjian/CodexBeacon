import CodexBeaconCore
import SwiftUI

private enum BeaconColor {
  static let red = Color(red: 0.95, green: 0.18, blue: 0.17)
  static let amber = Color(red: 0.98, green: 0.61, blue: 0.12)
  static let green = Color(red: 0.17, green: 0.82, blue: 0.36)
}

struct IdleBeaconView: View {
  let state: BeaconViewState
  let onActivate: () -> Void

  var body: some View {
    ZStack {
      BeaconSurface(surface: state.surface)
        .frame(
          width: state.dimensions.width,
          height: state.dimensions.height
        )

      if state.orientation == .vertical {
        VStack(spacing: 15) {
          lamps
          Spacer(minLength: 4)
          QuotaTrack(state: state.quotaTrack, orientation: .vertical)
        }
        .padding(.horizontal, 11)
        .padding(.top, 22)
        .padding(.bottom, 19)
      } else {
        HStack(spacing: 15) {
          lamps
          Spacer(minLength: 4)
          QuotaTrack(state: state.quotaTrack, orientation: .horizontal)
        }
        .padding(.vertical, 8)
        .padding(.leading, 19)
        .padding(.trailing, 22)
      }
    }
    .frame(
      width: state.dimensions.width,
      height: state.dimensions.height
    )
    .transaction { transaction in
      if state.reducesMotion {
        transaction.animation = nil
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Codex Beacon")
    .accessibilityValue(accessibilityValue)
    .onTapGesture(perform: onActivate)
  }

  @ViewBuilder
  private var lamps: some View {
    ForEach(Array(state.lights.enumerated()), id: \.offset) { _, light in
      LightRecess(light: light)
    }
  }

  private var accessibilityValue: String {
    switch state.status {
    case .idle:
      "Idle"
    case .working:
      "Working"
    case .waitingForYou:
      "Waiting for you"
    case .completed:
      "Completed"
    case .monitoringUnavailable:
      "Monitoring unavailable"
    }
  }
}

private struct BeaconSurface: View {
  let surface: BeaconSurfaceState

  var body: some View {
    switch surface.shape {
    case .roundedRectangle(let cornerRadius):
      ZStack {
        RoundedRectangle(cornerRadius: cornerRadius, style: .circular)
          .fill(.ultraThinMaterial)

        RoundedRectangle(cornerRadius: cornerRadius, style: .circular)
          .fill(surfaceColor.opacity(0.91))

        RoundedRectangle(cornerRadius: cornerRadius, style: .circular)
          .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
      }
    }
  }

  private var surfaceColor: Color {
    switch surface.tone {
    case .nearBlack:
      Color(red: 0.035, green: 0.039, blue: 0.045)
    }
  }
}

private struct LightRecess: View {
  let light: BeaconLightState

  var body: some View {
    Circle()
      .fill(Color.black.opacity(0.56))
      .overlay {
        Circle()
          .fill(color.opacity(illuminationOpacity))
          .padding(3)
      }
      .overlay {
        if light.showsRecess {
          Circle()
            .strokeBorder(color.opacity(0.19), lineWidth: 1)
        }
      }
      .overlay {
        Circle()
          .strokeBorder(Color.black.opacity(0.8), lineWidth: 2)
          .padding(1)
      }
      .frame(width: 32, height: 32)
      .shadow(color: .black.opacity(0.8), radius: 2, y: 1)
  }

  private var illuminationOpacity: Double {
    switch light.illumination {
    case .off:
      0.08
    case .steady:
      1
    }
  }

  private var color: Color {
    switch light.color {
    case .red:
      BeaconColor.red
    case .amber:
      BeaconColor.amber
    case .green:
      BeaconColor.green
    }
  }
}

private struct QuotaTrack: View {
  let state: QuotaTrackState
  let orientation: BeaconOrientation

  private var ringDiameter: Double { isVertical ? 36 : 32 }
  private var ringLineWidth: Double { isVertical ? 5 : 4 }
  private var isVertical: Bool { orientation == .vertical }

  var body: some View {
    Group {
      if state.style == .gauge, let selectedWindow {
        VStack(spacing: isVertical ? 4 : 3) {
          if let resetText = resetText(for: selectedWindow) {
            resetReadout(resetText)
          }
          gaugeRing(remainingText(for: selectedWindow))
        }
      } else {
        inactiveRing
      }
    }
    .allowsHitTesting(false)
  }

  private func gaugeRing(_ percentage: String) -> some View {
    ZStack {
      Circle()
        .stroke(trackBackgroundColor, lineWidth: ringLineWidth)

      Circle()
        .trim(from: 0, to: state.fillFraction)
        .stroke(
          gaugeFillColor,
          style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round)
        )
        .rotationEffect(.degrees(-90))

      Text(percentage)
        .font(.system(size: isVertical ? 11 : 10, weight: .semibold, design: .rounded))
        .foregroundStyle(.white.opacity(0.84))
        .monospacedDigit()
    }
    .frame(width: ringDiameter, height: ringDiameter)
  }

  private var inactiveRing: some View {
    Circle()
      .strokeBorder(
        inactiveRingColor,
        style: inactiveRingStyle
      )
      .frame(width: ringDiameter, height: ringDiameter)
  }

  private var gaugeFillColor: Color {
    let fraction = state.fillFraction
    if fraction > 0.5 {
      return BeaconColor.green
    } else if fraction > 0.15 {
      return BeaconColor.amber
    } else {
      return BeaconColor.red
    }
  }

  private var trackBackgroundColor: Color {
    switch state.style {
    case .neutral:
      Color.white.opacity(0.12)
    case .gauge:
      Color.white.opacity(0.08)
    case .dashed:
      Color.clear
    }
  }

  private var inactiveRingColor: Color {
    switch state.style {
    case .dashed:
      Color.white.opacity(0.13)
    case .neutral:
      Color.white.opacity(0.12)
    case .gauge:
      trackBackgroundColor
    }
  }

  private var inactiveRingStyle: StrokeStyle {
    switch state.style {
    case .dashed:
      StrokeStyle(lineWidth: 1, dash: [4, 4])
    case .neutral, .gauge:
      StrokeStyle(lineWidth: ringLineWidth)
    }
  }

  private var selectedWindow: QuotaWindow? {
    state.detailWindows
      .filter { $0.durationSeconds > 0 }
      .min { $0.durationSeconds < $1.durationSeconds }
  }

  private func resetReadout(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 7, weight: .medium, design: .rounded))
      .foregroundStyle(.white.opacity(0.56))
      .monospacedDigit()
      .fixedSize()
  }

  private func remainingText(for window: QuotaWindow) -> String {
    String(format: "%.0f%%", window.remainingPercentage)
  }

  private func resetText(for window: QuotaWindow) -> String? {
    guard let resetAt = window.resetAt else { return nil }
    let formatter = DateFormatter()
    formatter.dateFormat = "M/d HH:mm"
    return formatter.string(from: resetAt)
  }

}
