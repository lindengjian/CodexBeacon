import CodexBeaconCore
import SwiftUI

struct IdleBeaconView: View {
  let state: BeaconViewState
  let onActivate: () -> Void

  var body: some View {
    ZStack {
      BeaconSurface(surface: state.surface)
        .frame(
          width: state.size.dimensions.width,
          height: state.size.dimensions.height
        )

      VStack(spacing: 15) {
        ForEach(Array(state.lights.enumerated()), id: \.offset) { _, light in
          LightRecess(light: light)
        }

        Spacer(minLength: 4)

        QuotaTrack(state: state.quotaTrack)
      }
      .padding(.horizontal, 13)
      .padding(.top, 22)
      .padding(.bottom, 19)
    }
    .frame(
      width: state.size.dimensions.width,
      height: state.size.dimensions.height
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
      Color(red: 0.95, green: 0.18, blue: 0.17)
    case .amber:
      Color(red: 0.98, green: 0.61, blue: 0.12)
    case .green:
      Color(red: 0.17, green: 0.82, blue: 0.36)
    }
  }
}

private struct QuotaTrack: View {
  let state: QuotaTrackState

  var body: some View {
    Capsule()
      .fill(trackColor)
      .overlay {
        Capsule()
          .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
      }
      .frame(width: 8, height: 52)
  }

  private var trackColor: Color {
    switch state.style {
    case .neutral:
      Color.white.opacity(0.12)
    }
  }
}
