import AppKit
import Carbon
import CodexBeaconCore
import SwiftUI

@MainActor
final class BeaconSettingsWindowController: NSWindowController {
  init(rootView: BeaconSettingsView) {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 460, height: 690),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.title = "Beacon 设置"
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: rootView)
    window.center()
    super.init(window: window)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func present() {
    showWindow(nil)
    window?.makeKeyAndOrderFront(nil)
  }
}

@MainActor
final class InitialSetupWindowController: NSWindowController {
  init(rootView: InitialSetupView) {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 500, height: 450),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.title = "Codex Beacon 首次设置"
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: rootView)
    window.center()
    super.init(window: window)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func present() {
    showWindow(nil)
    window?.makeKeyAndOrderFront(nil)
  }
}

struct BeaconSettingsView: View {
  @StateObject private var model: BeaconSettingsModel
  let integrationSettings: BeaconIntegrationSettingsModel?

  init(
    size: BeaconSize,
    hotKey: BeaconHotKey,
    registrationError: String? = nil,
    showTaskTitles: Bool = false,
    soundPreferences: BeaconSoundPreferences = .init(),
    appearance: BeaconAppearance = .system,
    onSizeSelected: @escaping (BeaconSize) -> Void,
    onHotKeySelected: @escaping (BeaconHotKey) -> String?,
    onShowTaskTitlesChanged: @escaping (Bool) -> Void = { _ in },
    onSoundPreferencesChanged: @escaping (BeaconSoundPreferences) -> Void = { _ in },
    onAppearanceSelected: @escaping (BeaconAppearance) -> Void = { _ in },
    onSoundPreviewRequested: @escaping @MainActor (String) -> Void = { _ in },
    integrationSettings: BeaconIntegrationSettingsModel? = nil
  ) {
    _model = StateObject(
      wrappedValue: BeaconSettingsModel(
        size: size,
        hotKey: hotKey,
        registrationError: registrationError,
        showTaskTitles: showTaskTitles,
        soundPreferences: soundPreferences,
        appearance: appearance,
        onSizeSelected: onSizeSelected,
        onHotKeySelected: onHotKeySelected,
        onShowTaskTitlesChanged: onShowTaskTitlesChanged,
        onSoundPreferencesChanged: onSoundPreferencesChanged,
        onAppearanceSelected: onAppearanceSelected,
        onSoundPreviewRequested: onSoundPreviewRequested
      )
    )
    self.integrationSettings = integrationSettings
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 8) {
        Text("Beacon 尺寸")
        Picker("Beacon 尺寸", selection: Binding(
          get: { model.size },
          set: { newSize in model.selectSize(newSize) }
        )) {
          Text("标准（62 × 229 pt）").tag(BeaconSize.standard)
          Text("紧凑（24 × 88 pt）").tag(BeaconSize.compact)
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 220, alignment: .leading)
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("外观")
        HStack(spacing: 14) {
          ForEach(BeaconAppearance.allCases, id: \.self) { appearance in
            Button {
              model.selectAppearance(appearance)
            } label: {
              AppearancePreview(appearance: appearance, isSelected: model.appearance == appearance)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(appearance.displayName)
            .accessibilityValue(model.appearance == appearance ? "已选择" : "")
          }
        }
        Text("跟随系统会在 macOS 切换亮暗外观时立即同步。")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("全局显示/隐藏")
        HotKeyRecorder(
          hotKey: $model.hotKey,
          errorMessage: $model.hotKeyError,
          onHotKeySelected: model.recordHotKey
        )
        .frame(width: 158, height: 28)

        Text("点击快捷键，然后按下包含 ⌘、⌥、⌃ 或 ⇧ 的组合键。")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      if let hotKeyError = model.hotKeyError {
        Text(hotKeyError)
          .font(.caption)
          .foregroundStyle(.red)
      }

      VStack(alignment: .leading, spacing: 8) {
        Toggle(
          "显示任务标题",
          isOn: Binding(
            get: { model.showTaskTitles },
            set: { model.updateShowTaskTitles($0) }
          )
        )
        Text("开启后在悬停详情中显示任务标题。关闭后仅显示聚合计数。")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("事件声音")
        ForEach(BeaconSoundEvent.allCases, id: \.self) { event in
          HStack(spacing: 10) {
            Toggle(
              soundEventTitle(event),
              isOn: Binding(
                get: { model.soundPreferences[event].isEnabled },
                set: { model.updateSoundEnabled($0, for: event) }
              )
            )
            .frame(width: 108, alignment: .leading)

            Picker(
              "\(soundEventTitle(event))声音",
              selection: Binding(
                get: { model.soundPreferences[event].soundName },
                set: { model.updateSoundName($0, for: event) }
              )
            ) {
              ForEach(BeaconSystemSound.availableNames, id: \.self) { name in
                Text(name).tag(name)
              }
            }
            .labelsHidden()
            .frame(width: 150, alignment: .leading)

            Button {
              model.previewSound(for: event)
            } label: {
              Label("试听", systemImage: "play.fill")
            }
            .help("试听\(soundEventTitle(event))声音")
          }
        }
        Text("声音使用 macOS 内置提示音；每类事件可单独启用和选择。")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      if let integrationSettings {
        BeaconIntegrationSettingsSection(model: integrationSettings)
      }
    }
    .padding(20)
    .frame(width: 460, alignment: .topLeading)
  }

  private func soundEventTitle(_ event: BeaconSoundEvent) -> String {
    switch event {
    case .waiting: "审批"
    case .completion: "完成"
    case .quotaReset: "额度重置"
    }
  }
}

@MainActor
final class BeaconSettingsModel: ObservableObject {
  @Published private(set) var size: BeaconSize
  @Published var hotKey: BeaconHotKey
  @Published var hotKeyError: String?
  @Published private(set) var showTaskTitles: Bool
  @Published private(set) var soundPreferences: BeaconSoundPreferences
  @Published private(set) var appearance: BeaconAppearance

  private let onSizeSelected: (BeaconSize) -> Void
  private let onHotKeySelected: (BeaconHotKey) -> String?
  private let onShowTaskTitlesChanged: (Bool) -> Void
  private let onSoundPreferencesChanged: (BeaconSoundPreferences) -> Void
  private let onAppearanceSelected: (BeaconAppearance) -> Void
  private let onSoundPreviewRequested: @MainActor (String) -> Void

  init(
    size: BeaconSize,
    hotKey: BeaconHotKey,
    registrationError: String?,
    showTaskTitles: Bool = false,
    soundPreferences: BeaconSoundPreferences = .init(),
    appearance: BeaconAppearance = .system,
    onSizeSelected: @escaping (BeaconSize) -> Void,
    onHotKeySelected: @escaping (BeaconHotKey) -> String?,
    onShowTaskTitlesChanged: @escaping (Bool) -> Void = { _ in },
    onSoundPreferencesChanged: @escaping (BeaconSoundPreferences) -> Void = { _ in },
    onAppearanceSelected: @escaping (BeaconAppearance) -> Void = { _ in },
    onSoundPreviewRequested: @escaping @MainActor (String) -> Void = { _ in }
  ) {
    self.size = size
    self.hotKey = hotKey
    hotKeyError = registrationError
    self.showTaskTitles = showTaskTitles
    self.soundPreferences = soundPreferences
    self.appearance = appearance
    self.onSizeSelected = onSizeSelected
    self.onHotKeySelected = onHotKeySelected
    self.onShowTaskTitlesChanged = onShowTaskTitlesChanged
    self.onSoundPreferencesChanged = onSoundPreferencesChanged
    self.onAppearanceSelected = onAppearanceSelected
    self.onSoundPreviewRequested = onSoundPreviewRequested
  }

  func selectSize(_ size: BeaconSize) {
    guard self.size != size else {
      return
    }
    self.size = size
    onSizeSelected(size)
  }

  func recordHotKey(_ hotKey: BeaconHotKey) -> String? {
    if let error = onHotKeySelected(hotKey) {
      hotKeyError = error
      return error
    }
    self.hotKey = hotKey
    hotKeyError = nil
    return nil
  }

  func updateShowTaskTitles(_ enabled: Bool) {
    guard showTaskTitles != enabled else { return }
    showTaskTitles = enabled
    onShowTaskTitlesChanged(enabled)
  }

  func selectAppearance(_ appearance: BeaconAppearance) {
    guard self.appearance != appearance else { return }
    self.appearance = appearance
    onAppearanceSelected(appearance)
  }

  func updateSoundEnabled(_ enabled: Bool, for event: BeaconSoundEvent) {
    guard soundPreferences[event].isEnabled != enabled else { return }
    soundPreferences[event].isEnabled = enabled
    onSoundPreferencesChanged(soundPreferences)
  }

  func updateSoundName(_ name: String, for event: BeaconSoundEvent) {
    guard soundPreferences[event].soundName != name else { return }
    soundPreferences[event].soundName = name
    onSoundPreferencesChanged(soundPreferences)
  }

  func previewSound(for event: BeaconSoundEvent) {
    onSoundPreviewRequested(soundPreferences[event].soundName)
  }
}

private struct HotKeyRecorder: NSViewRepresentable {
  @Binding var hotKey: BeaconHotKey
  @Binding var errorMessage: String?
  let onHotKeySelected: (BeaconHotKey) -> String?

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  func makeNSView(context: Context) -> HotKeyRecorderButton {
    let button = HotKeyRecorderButton(hotKey: hotKey)
    button.delegate = context.coordinator
    return button
  }

  func updateNSView(_ button: HotKeyRecorderButton, context: Context) {
    button.hotKey = hotKey
  }

  @MainActor
  final class Coordinator: NSObject, HotKeyRecorderButtonDelegate {
    private let parent: HotKeyRecorder

    init(_ parent: HotKeyRecorder) {
      self.parent = parent
    }

    func hotKeyRecorder(_ recorder: HotKeyRecorderButton, recorded hotKey: BeaconHotKey) {
      if let error = parent.onHotKeySelected(hotKey) {
        parent.errorMessage = error
      } else {
        parent.hotKey = hotKey
        parent.errorMessage = nil
      }
    }

    func hotKeyRecorder(_ recorder: HotKeyRecorderButton, rejected reason: String) {
      parent.errorMessage = reason
    }
  }
}

@MainActor
private protocol HotKeyRecorderButtonDelegate: AnyObject {
  func hotKeyRecorder(_ recorder: HotKeyRecorderButton, recorded hotKey: BeaconHotKey)
  func hotKeyRecorder(_ recorder: HotKeyRecorderButton, rejected reason: String)
}

@MainActor
private final class HotKeyRecorderButton: NSButton {
  weak var delegate: HotKeyRecorderButtonDelegate?
  var hotKey: BeaconHotKey {
    didSet { updateTitle() }
  }
  private var isRecording = false {
    didSet { updateTitle() }
  }

  init(hotKey: BeaconHotKey) {
    self.hotKey = hotKey
    super.init(frame: .zero)
    bezelStyle = .rounded
    setButtonType(.momentaryPushIn)
    updateTitle()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var acceptsFirstResponder: Bool { true }

  override func mouseDown(with event: NSEvent) {
    isRecording = true
    window?.makeFirstResponder(self)
  }

  override func resignFirstResponder() -> Bool {
    isRecording = false
    return super.resignFirstResponder()
  }

  override func keyDown(with event: NSEvent) {
    guard event.keyCode != UInt16(kVK_Escape) else {
      isRecording = false
      window?.makeFirstResponder(nil)
      return
    }

    let hotKey = BeaconHotKey(
      keyCode: UInt32(event.keyCode),
      modifiers: carbonModifiers(from: event.modifierFlags)
    )
    guard hotKey.modifiers != 0 else {
      delegate?.hotKeyRecorder(
        self,
        rejected: "快捷键必须包含 ⌘、⌥、⌃ 或 ⇧ 修饰键。"
      )
      return
    }
    isRecording = false
    delegate?.hotKeyRecorder(self, recorded: hotKey)
  }

  private func updateTitle() {
    title = isRecording ? "按下快捷键…" : hotKey.displayName
  }
}

private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
  var modifiers: UInt32 = 0
  if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
  if flags.contains(.option) { modifiers |= UInt32(optionKey) }
  if flags.contains(.control) { modifiers |= UInt32(controlKey) }
  if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
  return modifiers
}

private extension BeaconHotKey {
  var displayName: String {
    var parts: [String] = []
    if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
    if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
    if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
    if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
    return parts.joined() + keyName
  }

  private var keyName: String {
    let names: [UInt32: String] = [
      UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
      UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
      UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
      UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
      UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
      UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
      UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
      UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
      UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
    ]
    return names[keyCode] ?? "键 \(keyCode)"
  }
}

private extension BeaconAppearance {
  var displayName: String {
    switch self {
    case .system: "跟随系统"
    case .light: "亮"
    case .dark: "暗"
    }
  }
}

private struct AppearancePreview: View {
  let appearance: BeaconAppearance
  let isSelected: Bool

  var body: some View {
    VStack(spacing: 6) {
      ZStack(alignment: .bottom) {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(previewBackground)

        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(previewSurface)
          .frame(width: 58, height: 30)
          .overlay(alignment: .topLeading) {
            Capsule()
              .fill(Color.accentColor)
              .frame(width: 38, height: 6)
              .padding(5)
          }
          .padding(8)
      }
      .frame(width: 92, height: 58)
      .overlay {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 3)
      }

      Text(appearance.displayName)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.primary)
    }
  }

  private var previewBackground: LinearGradient {
    switch appearance {
    case .system:
      LinearGradient(colors: [.gray.opacity(0.55), .blue.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
    case .light:
      LinearGradient(colors: [.white, .gray.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
    case .dark:
      LinearGradient(colors: [.blue.opacity(0.7), .black.opacity(0.95)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
  }

  private var previewSurface: Color {
    switch appearance {
    case .system, .light: .white.opacity(0.8)
    case .dark: .black.opacity(0.68)
    }
  }
}
