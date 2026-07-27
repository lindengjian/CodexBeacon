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
        .padding(.horizontal, 13)
        .padding(.top, 22)
        .padding(.bottom, 19)
      } else {
        HStack(spacing: 15) {
          lamps
          Spacer(minLength: 4)
          QuotaTrack(state: state.quotaTrack, orientation: .horizontal)
        }
        .padding(.vertical, 13)
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
  @State private var isHovering = false

  private var isVertical: Bool { orientation == .vertical }
  private var trackWidth: Double { isVertical ? 8 : 52 }
  private var trackHeight: Double { isVertical ? 52 : 8 }

  var body: some View {
    ZStack {
      if state.style == .dashed {
        dashedTrack
      } else {
        filledTrack
      }
    }
    .onHover { hovering in
      isHovering = hovering && state.style == .gauge && !state.detailWindows.isEmpty
    }
    .overlay(alignment: .top) {
      if isHovering {
        detailPopover
          .offset(y: -8)
      }
    }
  }

  private var filledTrack: some View {
    ZStack(alignment: isVertical ? .bottom : .leading) {
      Capsule()
        .fill(trackBackgroundColor)
      if state.style == .gauge {
        Capsule()
          .fill(gaugeFillColor)
          .frame(
            width: isVertical ? trackWidth : trackWidth * state.fillFraction,
            height: isVertical ? trackHeight * state.fillFraction : trackHeight
          )
      }
    }
    .frame(width: trackWidth, height: trackHeight)
    .clipShape(Capsule())
    .overlay {
      Capsule()
        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
    }
  }

  private var dashedTrack: some View {
    Capsule()
      .strokeBorder(
        Color.white.opacity(0.13),
        style: StrokeStyle(lineWidth: 1, dash: [4, 4])
      )
      .frame(width: trackWidth, height: trackHeight)
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

  private var detailPopover: some View {
    VStack(alignment: .leading, spacing: 4) {
      ForEach(state.detailWindows, id: \.windowKey) { window in
        HStack {
          Text(displayName(for: window))
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(.white.opacity(0.8))
          Spacer()
          Text(percentageText(for: window))
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(.white.opacity(0.9))
            .monospacedDigit()
        }
        if let resetText = resetText(for: window) {
          Text(resetText)
            .font(.system(size: 8))
            .foregroundColor(.white.opacity(0.4))
        }
        if window.windowKey != state.detailWindows.last?.windowKey {
          Divider()
            .background(Color.white.opacity(0.1))
        }
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(Color(red: 0.08, green: 0.08, blue: 0.10))
    )
    .overlay {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
    }
    .frame(minWidth: 160)
    .fixedSize()
  }

  private func displayName(for window: QuotaWindow) -> String {
    let hours = window.durationSeconds / 3600
    if hours >= 24 {
      let days = Int(hours / 24)
      return "\(days)d window"
    }
    if hours >= 1 {
      if hours == floor(hours) {
        return "\(Int(hours))h window"
      }
      return String(format: "%.1fh window", hours)
    }
    let minutes = Int(window.durationSeconds / 60)
    return "\(minutes)m window"
  }

  private func percentageText(for window: QuotaWindow) -> String {
    String(format: "%.0f%%", window.remainingPercentage)
  }

  private func resetText(for window: QuotaWindow) -> String? {
    guard let resetAt = window.resetAt else { return nil }
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d, HH:mm"
    return "resets \(formatter.string(from: resetAt))"
  }
}
