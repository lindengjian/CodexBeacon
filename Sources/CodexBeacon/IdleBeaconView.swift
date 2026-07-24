import CodexBeaconCore
import SwiftUI

struct IdleBeaconView: View {
  let state: BeaconViewState

  var body: some View {
    ZStack {
      Capsule()
        .fill(.ultraThinMaterial)

      Capsule()
        .fill(Color(red: 0.035, green: 0.039, blue: 0.045).opacity(0.91))

      Capsule()
        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)

      VStack(spacing: 15) {
        ForEach(Array(state.lights.enumerated()), id: \.offset) { _, light in
          LightRecess(light: light)
        }

        Spacer(minLength: 4)

        NeutralQuotaTrack()
      }
      .padding(.horizontal, 13)
      .padding(.top, 22)
      .padding(.bottom, 19)
    }
    .frame(
      width: state.size.dimensions.width,
      height: state.size.dimensions.height
    )
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Codex Beacon")
    .accessibilityValue("Idle")
  }
}

private struct LightRecess: View {
  let light: BeaconLightState

  var body: some View {
    Circle()
      .fill(Color.black.opacity(0.56))
      .overlay {
        Circle()
          .fill(color.opacity(0.08))
          .padding(3)
      }
      .overlay {
        Circle()
          .strokeBorder(color.opacity(0.19), lineWidth: 1)
      }
      .overlay {
        Circle()
          .strokeBorder(Color.black.opacity(0.8), lineWidth: 2)
          .padding(1)
      }
      .frame(width: 32, height: 32)
      .shadow(color: .black.opacity(0.8), radius: 2, y: 1)
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

private struct NeutralQuotaTrack: View {
  var body: some View {
    Capsule()
      .fill(Color.white.opacity(0.12))
      .overlay {
        Capsule()
          .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
      }
      .frame(width: 8, height: 52)
  }
}
