import ServiceManagement
import SwiftUI
import UserNotifications

enum DesktopIntegrationHealth: Equatable, Sendable {
  case ready
  case repairRequired
  case restartRequired
  case unavailable
}

struct DesktopIntegrationDiagnostic: Equatable, Sendable {
  let health: DesktopIntegrationHealth
  let summary: String
  let instructions: String
}

@MainActor
final class BeaconIntegrationSettingsModel: ObservableObject {
  @Published var launchesAtLogin: Bool
  @Published private(set) var notificationStatus: String
  @Published private(set) var diagnostic: DesktopIntegrationDiagnostic
  @Published private(set) var isWorking = false

  private let setLaunchAtLogin: (Bool) -> String?
  private let requestNotificationPermission: (@escaping @MainActor @Sendable (String) -> Void) -> Void
  private let readNotificationStatus: (@escaping @MainActor @Sendable (String) -> Void) -> Void
  private let diagnose: (@escaping @MainActor @Sendable (DesktopIntegrationDiagnostic) -> Void) -> Void
  private let repair: (@escaping @MainActor @Sendable (DesktopIntegrationDiagnostic) -> Void) -> Void
  private let restoreDefaultIntegration: (@escaping @MainActor @Sendable (DesktopIntegrationDiagnostic) -> Void) -> Void
  private let persistLaunchAtLogin: (Bool) -> Void

  init(
    launchesAtLogin: Bool,
    notificationStatus: String,
    diagnostic: DesktopIntegrationDiagnostic,
    setLaunchAtLogin: @escaping (Bool) -> String?,
    requestNotificationPermission: @escaping (@escaping @MainActor @Sendable (String) -> Void) -> Void,
    readNotificationStatus: @escaping (@escaping @MainActor @Sendable (String) -> Void) -> Void,
    diagnose: @escaping (@escaping @MainActor @Sendable (DesktopIntegrationDiagnostic) -> Void) -> Void,
    repair: @escaping (@escaping @MainActor @Sendable (DesktopIntegrationDiagnostic) -> Void) -> Void,
    restoreDefaultIntegration: @escaping (@escaping @MainActor @Sendable (DesktopIntegrationDiagnostic) -> Void) -> Void,
    persistLaunchAtLogin: @escaping (Bool) -> Void
  ) {
    self.launchesAtLogin = launchesAtLogin
    self.notificationStatus = notificationStatus
    self.diagnostic = diagnostic
    self.setLaunchAtLogin = setLaunchAtLogin
    self.requestNotificationPermission = requestNotificationPermission
    self.readNotificationStatus = readNotificationStatus
    self.diagnose = diagnose
    self.repair = repair
    self.restoreDefaultIntegration = restoreDefaultIntegration
    self.persistLaunchAtLogin = persistLaunchAtLogin
  }

  func updateLaunchAtLogin(_ enabled: Bool) {
    if let error = setLaunchAtLogin(enabled) {
      notificationStatus = error
      return
    }
    launchesAtLogin = enabled
    persistLaunchAtLogin(enabled)
  }

  func refresh() {
    isWorking = true
    readNotificationStatus { [weak self] status in
      self?.notificationStatus = status
    }
    diagnose { [weak self] diagnostic in
      self?.diagnostic = diagnostic
      self?.isWorking = false
    }
  }

  func requestNotifications() {
    isWorking = true
    requestNotificationPermission { [weak self] status in
      self?.notificationStatus = status
      self?.isWorking = false
    }
  }

  func repairIntegration() {
    isWorking = true
    repair { [weak self] diagnostic in
      self?.diagnostic = diagnostic
      self?.isWorking = false
    }
  }

  func restoreDefaultDesktopIntegration() {
    isWorking = true
    restoreDefaultIntegration { [weak self] diagnostic in
      self?.diagnostic = diagnostic
      self?.isWorking = false
    }
  }
}

struct BeaconIntegrationSettingsSection: View {
  @ObservedObject var model: BeaconIntegrationSettingsModel

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Divider()

      Toggle(
        "登录时启动 Beacon",
        isOn: Binding(
          get: { model.launchesAtLogin },
          set: { model.updateLaunchAtLogin($0) }
        )
      )

      VStack(alignment: .leading, spacing: 4) {
        Text("通知权限：\(model.notificationStatus)")
        Button("请求通知权限") { model.requestNotifications() }
          .disabled(model.isWorking)
      }

      VStack(alignment: .leading, spacing: 4) {
        Text("任务监测：\(model.diagnostic.summary)")
        Text(model.diagnostic.instructions)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        HStack {
          Button("重新运行诊断") { model.refresh() }
          if model.diagnostic.health != .ready {
            Button("修复集成") { model.repairIntegration() }
          }
          Button("恢复默认 Desktop 集成") { model.restoreDefaultDesktopIntegration() }
        }
        .disabled(model.isWorking)
      }
    }
  }
}

@MainActor
final class InitialSetupModel: ObservableObject {
  @Published var launchesAtLogin = true
  @Published private(set) var notificationStatus: String
  @Published private(set) var diagnostic: DesktopIntegrationDiagnostic
  @Published private(set) var isWorking = false
  @Published private(set) var completionError: String?

  private let requestNotificationPermission: (@escaping @MainActor @Sendable (String) -> Void) -> Void
  private let diagnose: (@escaping @MainActor @Sendable (DesktopIntegrationDiagnostic) -> Void) -> Void
  private let repair: (@escaping @MainActor @Sendable (DesktopIntegrationDiagnostic) -> Void) -> Void
  private let complete: (Bool) -> String?

  init(
    notificationStatus: String,
    diagnostic: DesktopIntegrationDiagnostic,
    requestNotificationPermission: @escaping (@escaping @MainActor @Sendable (String) -> Void) -> Void,
    diagnose: @escaping (@escaping @MainActor @Sendable (DesktopIntegrationDiagnostic) -> Void) -> Void,
    repair: @escaping (@escaping @MainActor @Sendable (DesktopIntegrationDiagnostic) -> Void) -> Void,
    complete: @escaping (Bool) -> String?
  ) {
    self.notificationStatus = notificationStatus
    self.diagnostic = diagnostic
    self.requestNotificationPermission = requestNotificationPermission
    self.diagnose = diagnose
    self.repair = repair
    self.complete = complete
  }

  func refresh() {
    isWorking = true
    diagnose { [weak self] diagnostic in
      self?.diagnostic = diagnostic
      self?.isWorking = false
    }
  }

  func requestNotifications() {
    isWorking = true
    requestNotificationPermission { [weak self] status in
      self?.notificationStatus = status
      self?.isWorking = false
    }
  }

  func repairIntegration() {
    isWorking = true
    repair { [weak self] diagnostic in
      self?.diagnostic = diagnostic
      self?.isWorking = false
    }
  }

  func finish() {
    completionError = complete(launchesAtLogin)
  }
}

struct InitialSetupView: View {
  @StateObject private var model: InitialSetupModel

  init(model: @autoclosure @escaping () -> InitialSetupModel) {
    _model = StateObject(wrappedValue: model())
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("欢迎使用 Codex Beacon")
        .font(.title2)
      Text("首次设置会验证本机 Codex Desktop 集成；不会读取或修改你的任务、认证信息、配置或私有记录。")
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)

      GroupBox("Codex Desktop 集成") {
        VStack(alignment: .leading, spacing: 8) {
          Text(model.diagnostic.summary)
          Text(model.diagnostic.instructions)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          HStack {
            Button("重新检测") { model.refresh() }
            if model.diagnostic.health != .ready {
              Button("修复集成") { model.repairIntegration() }
            }
          }
          .disabled(model.isWorking)
        }
      }

      GroupBox("通知") {
        HStack {
          Text("当前状态：\(model.notificationStatus)")
          Spacer()
          Button("请求权限") { model.requestNotifications() }
            .disabled(model.isWorking)
        }
      }

      Toggle("登录时启动 Beacon", isOn: $model.launchesAtLogin)

      HStack {
        Spacer()
        Button("完成设置") { model.finish() }
          .buttonStyle(.borderedProminent)
          .disabled(model.isWorking || model.diagnostic.health != .ready)
      }

      if let completionError = model.completionError {
        Text(completionError)
          .font(.caption)
          .foregroundStyle(.red)
      }
    }
    .padding(20)
    .frame(width: 500, alignment: .topLeading)
  }
}

enum BeaconSystemIntegration {
  static func notificationAuthorizationStatus(
    _ completion: @escaping @MainActor @Sendable (String) -> Void
  ) {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      let description = notificationStatusDescription(settings.authorizationStatus)
      DispatchQueue.main.async {
        completion(description)
      }
    }
  }

  static func requestNotificationAuthorization(
    _ completion: @escaping @MainActor @Sendable (String) -> Void
  ) {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in
      notificationAuthorizationStatus(completion)
    }
  }

  static func setLaunchAtLogin(_ enabled: Bool) -> String? {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      return nil
    } catch {
      return "无法更新登录启动：\(error.localizedDescription)"
    }
  }

  private static func notificationStatusDescription(_ status: UNAuthorizationStatus) -> String {
    switch status {
    case .notDetermined: "尚未请求"
    case .denied: "已拒绝（可在系统设置中更改）"
    case .authorized: "已允许"
    case .provisional: "临时允许"
    case .ephemeral: "临时会话允许"
    @unknown default: "未知"
    }
  }
}
