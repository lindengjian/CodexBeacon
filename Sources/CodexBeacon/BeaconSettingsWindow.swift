import AppKit
import Carbon
import CodexBeaconCore
import SwiftUI

@MainActor
final class BeaconSettingsWindowController: NSWindowController {
  init(rootView: BeaconSettingsView) {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 390, height: 230),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.title = "Beacon 设置"
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: rootView)
    super.init(window: window)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

struct BeaconSettingsView: View {
  @StateObject private var model: BeaconSettingsModel

  init(
    size: BeaconSize,
    hotKey: BeaconHotKey,
    registrationError: String? = nil,
    onSizeSelected: @escaping (BeaconSize) -> Void,
    onHotKeySelected: @escaping (BeaconHotKey) -> String?
  ) {
    _model = StateObject(
      wrappedValue: BeaconSettingsModel(
        size: size,
        hotKey: hotKey,
        registrationError: registrationError,
        onSizeSelected: onSizeSelected,
        onHotKeySelected: onHotKeySelected
      )
    )
  }

  var body: some View {
    Form {
      Picker("Beacon 尺寸", selection: Binding(
        get: { model.size },
        set: { newSize in model.selectSize(newSize) }
      )) {
        Text("标准（62 × 229 pt）").tag(BeaconSize.standard)
        Text("紧凑（24 × 88 pt）").tag(BeaconSize.compact)
      }

      HStack(alignment: .firstTextBaseline) {
        Text("全局显示/隐藏")
        Spacer()
        HotKeyRecorder(
          hotKey: $model.hotKey,
          errorMessage: $model.hotKeyError,
          onHotKeySelected: model.recordHotKey
        )
        .frame(width: 158, height: 28)
      }

      Text("点击快捷键，然后按下包含 ⌘、⌥、⌃ 或 ⇧ 的组合键。")
        .font(.caption)
        .foregroundStyle(.secondary)

      if let hotKeyError = model.hotKeyError {
        Text(hotKeyError)
          .font(.caption)
          .foregroundStyle(.red)
      }
    }
    .padding(20)
    .frame(width: 390, height: 230)
  }
}

@MainActor
final class BeaconSettingsModel: ObservableObject {
  @Published private(set) var size: BeaconSize
  @Published var hotKey: BeaconHotKey
  @Published var hotKeyError: String?

  private let onSizeSelected: (BeaconSize) -> Void
  private let onHotKeySelected: (BeaconHotKey) -> String?

  init(
    size: BeaconSize,
    hotKey: BeaconHotKey,
    registrationError: String?,
    onSizeSelected: @escaping (BeaconSize) -> Void,
    onHotKeySelected: @escaping (BeaconHotKey) -> String?
  ) {
    self.size = size
    self.hotKey = hotKey
    hotKeyError = registrationError
    self.onSizeSelected = onSizeSelected
    self.onHotKeySelected = onHotKeySelected
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
