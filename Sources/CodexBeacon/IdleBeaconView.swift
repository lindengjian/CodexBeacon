import CodexBeaconCore
import SwiftUI

private enum BeaconColor {
  static let red = Color(red: 0.95, green: 0.18, blue: 0.17)
  static let amber = Color(red: 0.98, green: 0.61, blue: 0.12)
  static let green = Color(red: 0.17, green: 0.82, blue: 0.36)
}

struct IdleBeaconView: View {
  @ObservedObject var stateStore: BeaconViewStateStore
  let onActivate: () -> Void
  @State private var isHovering = false

  private var state: BeaconViewState {
    stateStore.state
  }

  var body: some View {
    ZStack {
      BeaconSurface(surface: state.surface)
        .frame(
          width: state.dimensions.width,
          height: state.dimensions.height
        )

      if state.orientation == .vertical {
        VStack(spacing: isCompact ? 5 : 15) {
          lamps
          Spacer(minLength: isCompact ? 1 : 4)
          QuotaTrack(state: state.quotaTrack, orientation: .vertical, size: state.size)
        }
        .padding(.horizontal, isCompact ? 4 : 11)
        .padding(.top, isCompact ? 8 : 22)
        .padding(.bottom, isCompact ? 7 : 19)
      } else {
        HStack(spacing: isCompact ? 5 : 15) {
          lamps
          Spacer(minLength: isCompact ? 1 : 4)
          QuotaTrack(state: state.quotaTrack, orientation: .horizontal, size: state.size)
        }
        .padding(.vertical, isCompact ? 4 : 8)
        .padding(.leading, isCompact ? 7 : 19)
        .padding(.trailing, isCompact ? 8 : 22)
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
    .onHover { isHovering = $0 }
    .popover(isPresented: $isHovering, arrowEdge: state.orientation == .vertical ? .leading : .bottom) {
      if let detail = state.hoverDetail {
        HoverDetailView(detail: detail)
      }
    }
    .onTapGesture(perform: onActivate)
    .overlay(alignment: .center) {
      if let message = state.activeResetMessage {
        resetMessageOverlay(message)
      }
    }
  }

  private var isCompact: Bool {
    state.size == .compact
  }

  @ViewBuilder
  private var lamps: some View {
    ForEach(Array(state.lights.enumerated()), id: \.offset) { _, light in
      LightRecess(
        light: light,
        diameter: isCompact ? 14 : 32,
        reducesMotion: state.reducesMotion
      )
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

  private func resetMessageOverlay(_ message: String) -> some View {
    Text(message)
      .font(.system(size: isCompact ? 6 : 9, weight: .medium, design: .rounded))
      .foregroundStyle(.white.opacity(0.9))
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: true, vertical: false)
      .padding(.horizontal, 4)
      .padding(.vertical, 2)
      .background(
        RoundedRectangle(cornerRadius: 4, style: .circular)
          .fill(BeaconColor.green.opacity(0.7))
      )
      .padding(.bottom, 2)
      .transition(.opacity.animation(.easeInOut(duration: 0.3)))
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
  let diameter: Double
  let reducesMotion: Bool

  private var logic: LightRenderLogic {
    LightRenderLogic(illumination: light.illumination, reducesMotion: reducesMotion)
  }

  var body: some View {
    Circle()
      .fill(Color.black.opacity(0.56))
      .overlay {
        TimelineView(
          .animation(minimumInterval: 1.0 / 30.0, paused: !logic.shouldAnimate)
        ) { context in
          Circle()
            .fill(color.opacity(logic.showsWaitingRing ? 0 : logic.displayedOpacity(at: context.date)))
            .padding(diameter > 20 ? 3 : 1.5)
        }
      }
      .overlay {
        if logic.showsWaitingRing {
          Circle()
            .strokeBorder(color.opacity(0.9), lineWidth: diameter > 20 ? 1.5 : 0.75)
            .padding(diameter > 20 ? 5 : 2.5)
          Circle()
            .strokeBorder(color.opacity(0.9), lineWidth: diameter > 20 ? 1.5 : 0.75)
            .padding(diameter > 20 ? 10 : 4)
        }
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
      .frame(width: diameter, height: diameter)
      .shadow(color: .black.opacity(0.8), radius: 2, y: 1)
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
  let size: BeaconSize

  private var isCompact: Bool { size == .compact }
  private var ringDiameter: Double { isCompact ? 14 : (isVertical ? 36 : 32) }
  private var ringLineWidth: Double { isCompact ? 2 : (isVertical ? 5 : 4) }
  private var isVertical: Bool { orientation == .vertical }

  var body: some View {
    Group {
      if state.style == .gauge, let selectedWindow {
        VStack(spacing: isVertical ? 4 : 3) {
          if !isCompact, let resetText = resetText(for: selectedWindow) {
            resetReadout(resetText)
          }
          gaugeRing(isCompact ? nil : remainingText(for: selectedWindow))
        }
      } else {
        inactiveRing
      }
    }
    .allowsHitTesting(false)
  }

  private func gaugeRing(_ percentage: String?) -> some View {
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

      if let percentage {
        Text(percentage)
          .font(.system(size: isVertical ? 11 : 10, weight: .semibold, design: .rounded))
          .foregroundStyle(.white.opacity(0.84))
          .monospacedDigit()
      }
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

struct HoverDetailView: View {
  let detail: HoverDetailState

  private static let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "M/d HH:mm"
    return formatter
  }()

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      statusHeader

      if !detail.aggregateCountsDescription.isEmpty {
        Text(detail.aggregateCountsDescription)
          .font(.system(size: 12, weight: .semibold))
      }

      if detail.showTaskTitles, !detail.tasks.isEmpty {
        taskList
      }

      if !detail.quotaWindows.isEmpty {
        quotaSection
      }

      if let lastUpdated = detail.lastUpdatedAt {
        Text("更新于 \(Self.dateFormatter.string(from: lastUpdated))")
          .font(.system(size: 10))
          .foregroundStyle(.secondary)
      }

      if let taskError = detail.taskError {
        errorRow(icon: "exclamationmark.triangle", message: taskError)
      }
      if let quotaError = detail.quotaError {
        errorRow(icon: "chart.bar.xaxis", message: quotaError)
      }
    }
    .padding(12)
    .frame(minWidth: 200, maxWidth: 280)
  }

  private var statusHeader: some View {
    HStack(spacing: 6) {
      Circle()
        .fill(statusColor)
        .frame(width: 8, height: 8)
      Text(statusText)
        .font(.system(size: 13, weight: .medium))
    }
  }

  private var statusColor: Color {
    switch detail.status {
    case .idle:
      return .gray
    case .working:
      return Color(red: 0.98, green: 0.61, blue: 0.12)
    case .waitingForYou:
      return Color(red: 0.17, green: 0.82, blue: 0.36)
    case .completed:
      return Color(red: 0.17, green: 0.82, blue: 0.36)
    case .monitoringUnavailable:
      return Color(red: 0.95, green: 0.18, blue: 0.17)
    }
  }

  private var statusText: String {
    switch detail.status {
    case .idle:
      return "空闲"
    case .working:
      return "工作中"
    case .waitingForYou:
      return "等待你"
    case .completed:
      return "已完成"
    case .monitoringUnavailable:
      return "监测不可用"
    }
  }

  private var taskList: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("任务")
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.secondary)
      ForEach(detail.tasks, id: \.threadID) { task in
        HStack(spacing: 6) {
          Circle()
            .fill(taskStateColor(task.state))
            .frame(width: 6, height: 6)
          if let title = task.title {
            Text(title)
              .font(.system(size: 11))
              .lineLimit(1)
          } else if let sessionId = task.sessionId {
            Text(sessionId)
              .font(.system(size: 11))
              .lineLimit(1)
          } else {
            Text(taskStateText(task.state))
              .font(.system(size: 11))
          }
        }
      }
    }
  }

  private func taskStateColor(_ state: HoverTaskState) -> Color {
    switch state {
    case .working:
      return BeaconColor.amber
    case .waitingForYou:
      return BeaconColor.green
    case .completed:
      return BeaconColor.green
    }
  }

  private func taskStateText(_ state: HoverTaskState) -> String {
    switch state {
    case .working:
      return "工作中"
    case .waitingForYou:
      return "等待你"
    case .completed:
      return "已完成"
    }
  }

  private var quotaSection: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("额度")
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.secondary)
      ForEach(detail.quotaWindows, id: \.windowKey) { window in
        HStack {
          Text(quotaWindowLabel(window))
            .font(.system(size: 11))
          Spacer()
          Text(String(format: "%.0f%%", window.remainingPercentage))
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
          if let resetText = quotaResetText(window) {
            Text(resetText)
              .font(.system(size: 9))
              .foregroundStyle(.tertiary)
          }
        }
      }
    }
  }

  private func quotaWindowLabel(_ window: QuotaWindow) -> String {
    let mins = Int(window.durationSeconds / 60)
    if mins >= 1440 {
      return "\(mins / 1440)天"
    } else if mins >= 60 {
      return "\(mins / 60)小时"
    } else {
      return "\(mins)分钟"
    }
  }

  private func quotaResetText(_ window: QuotaWindow) -> String? {
    guard let resetAt = window.resetAt else { return nil }
    let formatter = DateFormatter()
    formatter.dateFormat = "M/d HH:mm"
    return formatter.string(from: resetAt)
  }

  private func errorRow(icon: String, message: String) -> some View {
    HStack(spacing: 6) {
      Image(systemName: icon)
        .font(.system(size: 10))
        .foregroundStyle(.red)
      Text(message)
        .font(.system(size: 10))
        .foregroundStyle(.red)
    }
  }
}
