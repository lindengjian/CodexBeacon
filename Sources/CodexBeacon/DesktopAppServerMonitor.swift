import AppKit
import CodexBeaconCore
import Darwin
import Foundation
import os

/// Connects only to Beacon's capability-validated shared daemon. It never
/// resumes a thread or replies to server requests. At login it restores the
/// persisted Desktop opt-in before waiting for Codex Desktop to connect.
final class DesktopAppServerMonitor: @unchecked Sendable {
  private static let snapshotInterval: TimeInterval = 5
  typealias EventHandler = (TaskEvent) -> Void
  typealias RequestsProvider = () -> [AppServerRequest]

  private let deliver: EventHandler
  private let requestsProvider: RequestsProvider
  private let socketPath: String
  private let bundledCLIURL: URL?
  private let compatibilityAdapter = DesktopDaemonCompatibilityAdapter()
  private let diagnosticStore: LocalDiagnosticStore
  private var client: UnixWebSocketClient?
  private var didInitialize = false
  private var sawSharedDesktopRuntime = false
  private var reconnectBackoff = MonitoringReconnectBackoff()
  private var retryWorkItem: DispatchWorkItem?
  private var snapshotTimer: DispatchSourceTimer?
  private var quotaRefreshInterval = QuotaRefreshSchedule.interval(for: .idle)
  private lazy var quotaRefreshTimer = QuotaRefreshTimer(
    interval: quotaRefreshInterval
  ) { [weak self] in
    guard let self, !self.isStopped else { return }
    self.dispatch([.quotaSnapshotRequested], flushesRequests: true)
  }
  private var quotaRefreshRequests: [Int: Date] = [:]
  private var consecutiveQuotaRefreshFailures = 0

  private enum FailureKind {
    case connection
    case runtimeEvidenceUnavailable
  }
  private var canRefreshQuota = false
  private var connectionAttemptInFlight = false
  private var compatibilityRepairInFlight = false
  private var connectionGeneration = 0
  private var isStopped = false

  private(set) var diagnostic = "Task monitoring has not started."

  init(
    deliver: @escaping EventHandler,
    requestsProvider: @escaping RequestsProvider,
    socketPath: String = DesktopAppServerMonitor.defaultSocketPath,
    bundledCLIURL: URL? = DesktopAppServerMonitor.findBundledCLI(),
    diagnosticStore: LocalDiagnosticStore = .init()
  ) {
    self.deliver = deliver
    self.requestsProvider = requestsProvider
    self.socketPath = socketPath
    self.bundledCLIURL = bundledCLIURL
    self.diagnosticStore = diagnosticStore
  }

  func start() {
    diagnosticStore.beginRun()
    diagnosticStore.record("lifecycle monitor_start")
    isStopped = false
    guard let bundledCLIURL else {
      attemptConnection()
      return
    }
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self else { return }
      _ = self.compatibilityAdapter.activateForCurrentLogin(bundledCLIURL: bundledCLIURL)
      DispatchQueue.main.async {
        guard !self.isStopped else { return }
        self.attemptConnection()
      }
    }
  }

  func stop() {
    diagnosticStore.record("lifecycle monitor_stop")
    isStopped = true
    retryWorkItem?.cancel()
    retryWorkItem = nil
    snapshotTimer?.cancel()
    snapshotTimer = nil
    quotaRefreshTimer.stop()
    quotaRefreshRequests.removeAll()
    consecutiveQuotaRefreshFailures = 0
    canRefreshQuota = false
    connectionAttemptInFlight = false
    connectionGeneration += 1
    client?.close()
    client = nil
    didInitialize = false
    sawSharedDesktopRuntime = false
  }

  /// Reports only local compatibility facts. Diagnosis is passive: it does not
  /// start a daemon, alter Desktop, or inspect task data.
  func diagnose(
    completion: @escaping @MainActor @Sendable (DesktopIntegrationDiagnostic) -> Void
  ) {
    let desktopApplicationURL = Self.findDesktopApplication()
    DispatchQueue.global(qos: .userInitiated).async { [bundledCLIURL, socketPath] in
      let diagnostic = Self.diagnostic(
        bundledCLIURL: bundledCLIURL,
        socketPath: socketPath,
        desktopApplicationURL: desktopApplicationURL,
        adapter: DesktopDaemonCompatibilityAdapter()
      )
      DispatchQueue.main.async { completion(diagnostic) }
    }
  }

  /// Manual recovery serializes repair requests. It only creates Beacon's
  /// labelled LaunchAgent and the next-process opt-in; it never stops Desktop.
  func repair(
    completion: @escaping @MainActor @Sendable (DesktopIntegrationDiagnostic) -> Void
  ) {
    guard !compatibilityRepairInFlight else {
      DispatchQueue.main.async {
        completion(
          .init(
            health: .restartRequired,
            summary: "共享 App Server 正在准备",
            instructions: "请等待当前修复完成；无需重复点击。"
          )
        )
      }
      return
    }
    compatibilityRepairInFlight = true
    DispatchQueue.global(qos: .userInitiated).async { [bundledCLIURL] in
      let adapter = DesktopDaemonCompatibilityAdapter()
      guard let bundledCLIURL else {
        DispatchQueue.main.async { [weak self] in
          self?.compatibilityRepairInFlight = false
          completion(
            .init(
              health: .unavailable,
              summary: "未找到 Codex Desktop",
              instructions: "请安装或重新安装 Codex Desktop，然后重新运行诊断。"
            )
          )
        }
        return
      }
      let result = adapter.prepare(bundledCLIURL: bundledCLIURL)
      let diagnostic: DesktopIntegrationDiagnostic
      if let result {
        diagnostic = .init(
          health: .unavailable,
          summary: "无法修复共享 App Server 集成",
          instructions: "\(result)\n本地诊断：\(adapter.diagnosticPath.path)"
        )
      } else {
        diagnostic = .init(
          health: .restartRequired,
          summary: "共享 App Server 已准备，等待重启 Codex Desktop",
          instructions: "请先在 Codex 中保存工作，再完全退出并重新打开 Codex Desktop。Beacon 不会替你终止任务或关闭应用；重启后重新运行诊断。"
        )
      }
      DispatchQueue.main.async { [weak self] in
        self?.compatibilityRepairInFlight = false
        completion(diagnostic)
      }
    }
  }

  /// Removes only Beacon's labelled compatibility adapter and restores the
  /// launchd environment value that existed before Beacon changed it.
  func restoreDefaultIntegration(
    completion: @escaping @MainActor @Sendable (DesktopIntegrationDiagnostic) -> Void
  ) {
    DispatchQueue.global(qos: .userInitiated).async {
      let adapter = DesktopDaemonCompatibilityAdapter()
      adapter.rollback()
      let diagnostic = DesktopIntegrationDiagnostic(
        health: .restartRequired,
        summary: "已恢复默认 Desktop 集成",
        instructions: "请完全退出并重新打开 Codex Desktop，以恢复其默认私有 App Server 拓扑。Beacon 没有修改任何任务、认证信息、配置或私有记录。"
      )
      DispatchQueue.main.async { completion(diagnostic) }
    }
  }

  private func attemptConnection() {
    guard !isStopped, !connectionAttemptInFlight else {
      diagnosticStore.record(
        "connection attempt_skipped stopped=\(isStopped) in_flight=\(connectionAttemptInFlight)"
      )
      return
    }
    connectionAttemptInFlight = true
    diagnosticStore.record("connection attempt_started")

    guard let bundledCLIURL else {
      connectionAttemptFailed("Codex Desktop's bundled CLI was not found. Open Settings to run local integration diagnostics.")
      return
    }
    guard FileManager.default.isExecutableFile(atPath: bundledCLIURL.path) else {
      connectionAttemptFailed("Codex Desktop's bundled CLI is not executable.")
      return
    }
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self else { return }
      guard FileManager.default.fileExists(atPath: self.socketPath) else {
        DispatchQueue.main.async {
          self.connectionAttemptFailed("The shared App Server is not ready. Open Settings to diagnose or repair the integration; Beacon will remain unavailable until shared Desktop runtime evidence is observed.")
        }
        return
      }
      self.diagnosticStore.record("connection socket_exists=true")
      DispatchQueue.main.async {
        self.connectionAttemptInFlight = false
        guard !self.isStopped else { return }
        self.connect()
      }
    }
  }

  private func connectionAttemptFailed(_ reason: String) {
    connectionAttemptInFlight = false
    diagnosticStore.record("connection attempt_failed reason=\(reason)")
    fail(reason)
  }

  private func connect() {
    guard !isStopped else { return }
    connectionGeneration += 1
    let generation = connectionGeneration
    diagnosticStore.record("connection socket_connect generation=\(generation)")
    let client = UnixWebSocketClient(
      socketPath: socketPath,
      received: { [weak self] message in self?.received(message, from: generation) },
      failed: { [weak self] message in self?.connectionFailed(message, from: generation) }
    )
    self.client = client
    client.connect()
  }

  private func received(_ message: String, from generation: Int) {
    guard !isStopped, generation == connectionGeneration else { return }
    guard let object = try? JSONSerialization.jsonObject(with: Data(message.utf8)) as? [String: Any] else {
      diagnosticStore.record("protocol receive_invalid_json generation=\(generation)")
      fail("The shared App Server sent invalid JSON.")
      return
    }

    recordQuotaRefreshResponse(from: object)

    if !didInitialize {
      guard object["id"] as? Int == 1, object["error"] == nil else {
        fail("The shared App Server rejected passive initialization.")
        return
      }
      didInitialize = true
      diagnosticStore.record("connection passive_initialization_accepted")
      client?.send(["method": "initialized"])
      canRefreshQuota = true
      startQuotaRefreshTimer()
      dispatch(
        [.monitoringConnectionEstablished(protocolCompatible: true)],
        flushesRequests: true
      )
      DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
        guard
          let self,
          generation == self.connectionGeneration,
          self.didInitialize,
          !self.sawSharedDesktopRuntime
        else { return }
        self.fail(
          "No loaded Codex Desktop runtime thread was observed. The shared daemon is reachable, but the currently running Codex Desktop process has not joined it. Fully quit and reopen Codex Desktop; Beacon will retry automatically.",
          kind: .runtimeEvidenceUnavailable
        )
      }
      return
    }

    // A request from the server intentionally has no response. Beacon is an
    // observer and must not take ownership of Desktop approvals or input.
    if object["id"] != nil, object["method"] != nil {
      diagnosticStore.record("protocol passive_observer_request_rejected")
      fail("The shared daemon sent this passive observer a request requiring a response. Monitoring stopped without responding.")
      return
    }

    let hasSharedDesktopRuntime: Bool
    if let thread = ((object["result"] as? [String: Any])?["thread"] as? [String: Any]),
      thread["source"] as? String == "vscode",
      thread["ephemeral"] as? Bool == false,
      thread["threadSource"] as? String != "system",
      thread["parentThreadId"] == nil || thread["parentThreadId"] is NSNull
    {
      hasSharedDesktopRuntime = !sawSharedDesktopRuntime
      if hasSharedDesktopRuntime {
        sawSharedDesktopRuntime = true
        reconnectBackoff.recordSuccessfulConnection()
        compatibilityAdapter.sharedRuntimeEvidenceObserved()
        diagnosticStore.record("runtime shared_desktop_evidence_observed")
      }
    } else {
      hasSharedDesktopRuntime = false
    }

    var events: [TaskEvent] = [.appServerMessage(message)]
    if hasSharedDesktopRuntime {
      events.append(.monitoringRuntimeValidated)
      startSnapshotTimer()
    }
    dispatch(events, flushesRequests: true)
  }

  private func connectionFailed(_ reason: String, from generation: Int) {
    guard !isStopped, generation == connectionGeneration else { return }
    diagnosticStore.record("connection socket_failed generation=\(generation) reason=\(reason)")
    fail(reason)
  }

  private func flushRequests() {
    for request in requestsProvider() {
      var params: [String: Any] = [:]
      if let threadID = request.threadID {
        params["threadId"] = threadID
      }
      if request.method == "thread/read" {
        params["includeTurns"] = false
      }
      if request.method == "thread/turns/list" {
        params["limit"] = 1
        params["sortDirection"] = "desc"
        params["itemsView"] = "summary"
      }
      if request.method == "account/rateLimits/read" {
        recordQuotaRefreshRequest(request.id)
      }
      client?.send(["id": request.id, "method": request.method, "params": params])
    }
  }

  private func fail(_ reason: String, kind: FailureKind = .connection) {
    guard !isStopped else { return }
    connectionGeneration += 1
    diagnostic = reason
    diagnosticStore.record(reason)
    Logger(subsystem: "com.codexbeacon", category: "task-monitoring").error("\(reason, privacy: .public)")
    client?.close()
    client = nil
    snapshotTimer?.cancel()
    snapshotTimer = nil
    quotaRefreshTimer.stop()
    quotaRefreshRequests.removeAll()
    consecutiveQuotaRefreshFailures = 0
    canRefreshQuota = false
    didInitialize = false
    sawSharedDesktopRuntime = false
    let event: TaskEvent = switch kind {
    case .connection:
      .monitoringConnectionFailed
    case .runtimeEvidenceUnavailable:
      .monitoringRuntimeEvidenceUnavailable
    }
    dispatch([event])
    scheduleReconnect()
  }

  private func scheduleReconnect() {
    guard !isStopped, retryWorkItem == nil else {
      return
    }
    let delay = reconnectBackoff.nextDelayAfterFailure()
    diagnosticStore.record("connection reconnect_scheduled delay_seconds=\(delay)")
    let workItem = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.retryWorkItem = nil
      self.attemptConnection()
    }
    retryWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
  }

  private func startSnapshotTimer() {
    guard snapshotTimer == nil, !isStopped else {
      return
    }
    let timer = DispatchSource.makeTimerSource(queue: .main)
    diagnosticStore.record("snapshot_timer started interval_seconds=\(Self.snapshotInterval)")
    timer.schedule(
      deadline: .now() + Self.snapshotInterval,
      repeating: Self.snapshotInterval,
      leeway: .milliseconds(250)
    )
    timer.setEventHandler { [weak self] in
      guard let self, !self.isStopped else {
        return
      }
      self.dispatch([.monitoringSnapshotRequested], flushesRequests: true)
    }
    snapshotTimer = timer
    timer.resume()
  }

  private func startQuotaRefreshTimer() {
    guard canRefreshQuota, !isStopped else {
      return
    }
    quotaRefreshTimer.start()
  }

  func updateQuotaRefreshInterval(for status: BeaconStatus) {
    let interval = QuotaRefreshSchedule.interval(for: status)
    guard quotaRefreshInterval != interval else {
      return
    }
    quotaRefreshInterval = interval
    diagnosticStore.record("quota_refresh interval_changed status=\(status.traceName) seconds=\(interval)")
    guard canRefreshQuota else {
      return
    }
    quotaRefreshTimer.update(interval: interval)
  }

  private func recordQuotaRefreshRequest(_ requestID: Int) {
    let now = Date()
    let timedOutRequestIDs = quotaRefreshRequests.compactMap { requestID, sentAt in
      now.timeIntervalSince(sentAt) >= 60 ? requestID : nil
    }
    for timedOutRequestID in timedOutRequestIDs {
      quotaRefreshRequests.removeValue(forKey: timedOutRequestID)
      recordQuotaRefreshFailure(
        requestID: timedOutRequestID,
        reason: "response_timeout_after_60_seconds"
      )
    }
    quotaRefreshRequests[requestID] = now
  }

  private func recordQuotaRefreshResponse(from object: [String: Any]) {
    guard
      let requestID = object["id"] as? Int,
      let sentAt = quotaRefreshRequests.removeValue(forKey: requestID)
    else {
      return
    }
    let elapsedMilliseconds = Int(Date().timeIntervalSince(sentAt) * 1_000)
    if let error = object["error"] as? [String: Any] {
      recordQuotaRefreshFailure(
        requestID: requestID,
        reason: Self.quotaRefreshErrorReason(for: error),
        latencyMilliseconds: elapsedMilliseconds
      )
      return
    }
    guard (object["result"] as? [String: Any])?["rateLimits"] != nil else {
      recordQuotaRefreshFailure(
        requestID: requestID,
        reason: "response_missing_rate_limits",
        latencyMilliseconds: elapsedMilliseconds
      )
      return
    }
    consecutiveQuotaRefreshFailures = 0
  }

  private func recordQuotaRefreshFailure(
    requestID: Int,
    reason: String,
    latencyMilliseconds: Int? = nil
  ) {
    consecutiveQuotaRefreshFailures += 1
    let latency = latencyMilliseconds.map { " latency_ms=\($0)" } ?? ""
    let message = "[quota-refresh] failed attempt=\(consecutiveQuotaRefreshFailures) id=\(requestID)\(latency) reason=\(reason)"
    diagnosticStore.record(message)
    Logger(subsystem: "com.codexbeacon", category: "quota-refresh").error(
      "\(message, privacy: .public)"
    )
  }

  private func dispatch(_ events: [TaskEvent], flushesRequests: Bool = false) {
    DispatchQueue.main.async { [weak self] in
      guard let self, !self.isStopped else {
        return
      }
      events.forEach(self.deliver)
      if flushesRequests {
        self.flushRequests()
      }
    }
  }

  private static let defaultSocketPath =
    (FileManager.default.homeDirectoryForCurrentUser.path as NSString)
      .appendingPathComponent(".codex/app-server-control/app-server-control.sock")

  static func quotaRefreshErrorReason(for error: [String: Any]) -> String {
    let code = error["code"].map { String(describing: $0) } ?? "unknown"
    return "server_error code=\(code)"
  }

  static func diagnosticEntry(forReceivedMessage message: String) -> String {
    guard let object = try? JSONSerialization.jsonObject(with: Data(message.utf8)) as? [String: Any] else {
      return "kind=invalid_json"
    }
    return diagnosticEntry(for: object)
  }

  private static func diagnosticEntry(for object: [String: Any]) -> String {
    var fields: [String] = []
    if let id = object["id"] {
      fields.append("id=\(id)")
    }
    if let method = object["method"] as? String {
      fields.append("method=\(method)")
    }
    if object["error"] != nil {
      fields.append("error=true")
    }

    if let params = object["params"] as? [String: Any],
      params["threadId"] is String
    {
      fields.append("thread=true")
      fields.append(contentsOf: threadStatusFields(params["status"]))
    }

    if let result = object["result"] as? [String: Any] {
      if let threadIDs = result["data"] as? [String] {
        fields.append("thread_count=\(threadIDs.count)")
      }
      if let thread = result["thread"] as? [String: Any] {
        fields.append("thread=true")
        if let source = thread["source"] {
          fields.append("source=\(source)")
        }
        if let threadSource = thread["threadSource"] as? String {
          fields.append("thread_source=\(threadSource)")
        }
        if let ephemeral = thread["ephemeral"] as? Bool {
          fields.append("ephemeral=\(ephemeral)")
        }
        fields.append(contentsOf: threadStatusFields(thread["status"]))
      }
      if result["rateLimits"] != nil {
        fields.append("rate_limits=true")
      }
    }

    return fields.isEmpty ? "kind=unclassified" : fields.joined(separator: " ")
  }

  private static func threadStatusFields(_ value: Any?) -> [String] {
    guard let status = value as? [String: Any] else { return [] }
    var fields: [String] = []
    if let type = status["type"] as? String {
      fields.append("status_type=\(type)")
    }
    if let flags = status["activeFlags"] as? [String] {
      fields.append("active_flags=\(flags.joined(separator: ","))")
    }
    return fields
  }

  private static func findBundledCLI() -> URL? {
    let desktopURL = findDesktopApplication()
    let candidates = [
      desktopURL?.appendingPathComponent("Contents/Resources/codex"),
      URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex"),
      URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex"),
    ].compactMap { $0 }
    return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
  }

  private static func findDesktopApplication() -> URL? {
    let codexURL = URL(string: "codex://threads/new")
    let appURL = codexURL.flatMap { NSWorkspace.shared.urlForApplication(toOpen: $0) }
    let candidates = [
      appURL,
      URL(fileURLWithPath: "/Applications/ChatGPT.app"),
      URL(fileURLWithPath: "/Applications/Codex.app"),
    ].compactMap { $0 }
    return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
  }

  private static func diagnostic(
    bundledCLIURL: URL?,
    socketPath: String,
    desktopApplicationURL: URL?,
    adapter: DesktopDaemonCompatibilityAdapter
  ) -> DesktopIntegrationDiagnostic {
    guard let desktopApplicationURL else {
      return .init(
        health: .unavailable,
        summary: "未检测到 Codex Desktop",
        instructions: "请安装 Codex Desktop，然后重新运行诊断。"
      )
    }
    guard let desktopVersion = desktopVersion(at: desktopApplicationURL) else {
      return .init(
        health: .unavailable,
        summary: "无法读取 Codex Desktop 版本",
        instructions: "请重新安装 Codex Desktop；Beacon 会在版本信息不可用时保持监测不可用。"
      )
    }
    guard let bundledCLIURL, FileManager.default.isExecutableFile(atPath: bundledCLIURL.path) else {
      return .init(
        health: .unavailable,
        summary: "Codex Desktop 的内置 CLI 不可用",
        instructions: "请重新安装 Codex Desktop；Beacon 不会尝试使用外部 CLI 替代它。"
      )
    }
    guard FileManager.default.fileExists(atPath: socketPath) else {
      return .init(
        health: adapter.isPrepared ? .restartRequired : .repairRequired,
        summary: adapter.isPrepared ? "等待重启 Codex Desktop" : "共享 App Server 尚未准备",
        instructions: adapter.isPrepared
          ? "请完全退出并重新打开 Codex Desktop，然后重新运行诊断。"
          : "选择“修复集成”以准备共享守护进程适配器；Beacon 会随后通过实际协议能力验证。"
      )
    }
    return .init(
      health: .ready,
      summary: "Codex Desktop \(desktopVersion) 的共享 App Server 已发现",
      instructions: "Beacon 将通过 App Server 协议握手和已加载的 Desktop 运行态证据验证监测；若失败，将保持监测不可用并写入本地诊断。"
    )
  }

  private static func desktopVersion(at applicationURL: URL) -> String? {
    let bundle = Bundle(url: applicationURL)
    return bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      ?? bundle?.object(forInfoDictionaryKey: "CFBundleVersion") as? String
  }
}

private extension BeaconStatus {
  var traceName: String {
    switch self {
    case .idle: "idle"
    case .working: "working"
    case .waitingForYou: "waiting_for_you"
    case .completed: "completed"
    case .monitoringUnavailable: "monitoring_unavailable"
    }
  }
}

private extension TaskEvent {
  var traceDescription: String {
    switch self {
    case .monitoringConnectionEstablished(let protocolCompatible):
      "monitoring_connection_established(protocol_compatible=\(protocolCompatible))"
    case .monitoringRuntimeValidated:
      "monitoring_runtime_validated"
    case .monitoringRuntimeEvidenceUnavailable:
      "monitoring_runtime_evidence_unavailable"
    case .monitoringConnectionFailed:
      "monitoring_connection_failed"
    case .monitoringObservationBecameStale:
      "monitoring_observation_became_stale"
    case .monitoringSnapshotRequested:
      "monitoring_snapshot_requested"
    case .quotaSnapshotRequested:
      "quota_snapshot_requested"
    case .appServerMessage:
      "app_server_message"
    }
  }
}

private final class UnixWebSocketClient: @unchecked Sendable {
  private let socketPath: String
  private let received: (String) -> Void
  private let failed: (String) -> Void
  private var socket: FileHandle?
  private var frameDecoder = WebSocketFrameDecoder()
  private var isUpgraded = false

  init(socketPath: String, received: @escaping (String) -> Void, failed: @escaping (String) -> Void) {
    self.socketPath = socketPath
    self.received = received
    self.failed = failed
  }

  func connect() {
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self else { return }
      let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
      guard descriptor >= 0 else { self.reportFailure("Unable to create the App Server socket."); return }
      var address = sockaddr_un()
      address.sun_family = sa_family_t(AF_UNIX)
      let bytes = Array(self.socketPath.utf8) + [0]
      guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
        Darwin.close(descriptor)
        self.reportFailure("The App Server socket path is too long.")
        return
      }
      withUnsafeMutableBytes(of: &address.sun_path) { destination in
        destination.copyBytes(from: bytes)
      }
      let connected = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
          Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
      }
      guard connected == 0 else { Darwin.close(descriptor); self.reportFailure("Unable to connect to the shared App Server socket."); return }
      DispatchQueue.main.async { self.begin(using: FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)) }
    }
  }

  func close() {
    socket?.readabilityHandler = nil
    try? socket?.close()
    socket = nil
  }

  func send(_ message: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }
    sendFrame(opcode: 0x1, payload: data)
  }

  private func begin(using socket: FileHandle) {
    self.socket = socket
    socket.readabilityHandler = { [weak self] handle in
      let data = handle.availableData
      guard !data.isEmpty else { self?.reportFailure("The shared App Server connection closed."); return }
      DispatchQueue.main.async { self?.consume(data) }
    }
    let key = Data(UUID().uuidString.utf8).base64EncodedString()
    let request = "GET / HTTP/1.1\r\nHost: localhost\r\nConnection: Upgrade\r\nUpgrade: websocket\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: \(key)\r\n\r\n"
    try? socket.write(contentsOf: Data(request.utf8))
  }

  private func consume(_ data: Data) {
    frameDecoder.append(data)
    if !isUpgraded {
      guard let response = frameDecoder.consumeHTTPUpgradeResponse() else { return }
      guard response.hasPrefix("HTTP/1.1 101") else { reportFailure("The App Server rejected the WebSocket upgrade."); return }
      isUpgraded = true
      send(["id": 1, "method": "initialize", "params": [
        "clientInfo": ["name": "codex-beacon", "title": "Codex Beacon passive observer", "version": "1.0.8"],
        "capabilities": ["experimentalApi": true],
      ]])
    }
    while frameDecoder.hasBufferedData {
      let byteCountBeforeParsing = frameDecoder.bufferedByteCount
      guard let frame = frameDecoder.nextFrame() else { break }
      switch frame.opcode {
      case 0x8:
        reportFailure("The shared App Server closed the WebSocket.")
        return
      case 0x9:
        sendFrame(opcode: 0xA, payload: frame.payload)
      case 0x1:
        if let message = String(data: frame.payload, encoding: .utf8) {
          received(message)
        }
      default:
        break
      }
      guard frameDecoder.bufferedByteCount < byteCountBeforeParsing else { break }
    }
  }

  private func sendFrame(opcode: UInt8, payload: Data) {
    guard let socket else { return }
    var frame = Data([0x80 | opcode])
    let mask = (0..<4).map { _ in UInt8.random(in: .min ... .max) }
    if payload.count < 126 { frame.append(0x80 | UInt8(payload.count)) }
    else { frame.append(0x80 | 126); frame.append(UInt8(payload.count >> 8)); frame.append(UInt8(payload.count & 0xFF)) }
    frame.append(contentsOf: mask)
    frame.append(contentsOf: payload.enumerated().map { $0.element ^ mask[$0.offset % 4] })
    try? socket.write(contentsOf: frame)
  }

  private func reportFailure(_ reason: String) { DispatchQueue.main.async { self.failed(reason) } }
}

struct WebSocketFrameDecoder {
  struct Frame {
    let opcode: UInt8
    let payload: Data
  }

  private var buffer = Data()

  var hasBufferedData: Bool { !buffer.isEmpty }
  var bufferedByteCount: Int { buffer.count }

  mutating func append(_ data: Data) {
    buffer.append(data)
  }

  mutating func consumeHTTPUpgradeResponse() -> String? {
    guard let range = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
    let response = String(decoding: buffer[..<range.lowerBound], as: UTF8.self)
    buffer.removeSubrange(..<range.upperBound)
    return response
  }

  mutating func nextFrame() -> Frame? {
    guard buffer.count >= 2 else { return nil }
    let bytes = [UInt8](buffer)
    let opcode = bytes[0] & 0x0F
    var offset = 2
    var length = Int(bytes[1] & 0x7F)

    if length == 126 {
      guard bytes.count >= 4 else { return nil }
      length = Int(bytes[2]) << 8 | Int(bytes[3])
      offset = 4
    }
    if length == 127 {
      guard bytes.count >= 10 else { return nil }
      let extendedLength = bytes[2..<10].reduce(UInt64(0)) { partial, byte in
        (partial << 8) | UInt64(byte)
      }
      guard extendedLength <= UInt64(Int.max) else { return nil }
      length = Int(extendedLength)
      offset = 10
    }
    guard length <= bytes.count - offset else { return nil }

    let payload = Data(bytes[offset..<(offset + length)])
    buffer.removeSubrange(..<(offset + length))
    return Frame(opcode: opcode, payload: payload)
  }
}
