import AppKit
import CodexBeaconCore
import Darwin
import Foundation
import os

/// Connects only to the daemon already selected by Codex Desktop. It never
/// launches an independent App Server, resumes a thread, or replies to server
/// requests. Desktop adoption is deliberately an explicit repair action
/// outside this passive observer.
final class DesktopAppServerMonitor: @unchecked Sendable {
  typealias EventHandler = (TaskEvent) -> Void
  typealias RequestsProvider = () -> [AppServerRequest]

  private let deliver: EventHandler
  private let requestsProvider: RequestsProvider
  private let socketPath: String
  private let bundledCLIURL: URL?
  private let compatibilityAdapter = DesktopDaemonCompatibilityAdapter()
  private let diagnosticStore = LocalDiagnosticStore()
  private var client: UnixWebSocketClient?
  private var didInitialize = false
  private var sawSharedDesktopRuntime = false
  private var reconnectBackoff = MonitoringReconnectBackoff()
  private var retryWorkItem: DispatchWorkItem?
  private var connectionAttemptInFlight = false
  private var connectionGeneration = 0
  private var isStopped = false

  private(set) var diagnostic = "Task monitoring has not started."

  init(
    deliver: @escaping EventHandler,
    requestsProvider: @escaping RequestsProvider,
    socketPath: String = DesktopAppServerMonitor.defaultSocketPath,
    bundledCLIURL: URL? = DesktopAppServerMonitor.findBundledCLI()
  ) {
    self.deliver = deliver
    self.requestsProvider = requestsProvider
    self.socketPath = socketPath
    self.bundledCLIURL = bundledCLIURL
  }

  func start() {
    isStopped = false
    attemptConnection()
  }

  func stop() {
    isStopped = true
    retryWorkItem?.cancel()
    retryWorkItem = nil
    connectionAttemptInFlight = false
    connectionGeneration += 1
    client?.close()
    client = nil
    didInitialize = false
    sawSharedDesktopRuntime = false
  }

  private func attemptConnection() {
    guard !isStopped, !connectionAttemptInFlight else {
      return
    }
    connectionAttemptInFlight = true

    guard let bundledCLIURL else {
      connectionAttemptFailed("Codex Desktop's bundled CLI was not found.")
      return
    }
    guard FileManager.default.isExecutableFile(atPath: bundledCLIURL.path) else {
      connectionAttemptFailed("Codex Desktop's bundled CLI is not executable.")
      return
    }
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self else { return }
      guard let cliVersion = Self.cliVersion(at: bundledCLIURL) else {
        DispatchQueue.main.async { self.connectionAttemptFailed("The bundled Codex CLI version could not be read.") }
        return
      }
      guard FileManager.default.fileExists(atPath: self.socketPath) else {
        let adoptionFailure = self.compatibilityAdapter.prepare(
          bundledCLIURL: bundledCLIURL,
          cliVersion: cliVersion
        )
        DispatchQueue.main.async {
          self.connectionAttemptFailed(adoptionFailure ?? "The shared daemon was prepared. Fully quit and reopen Codex Desktop; Beacon will reconnect automatically when shared runtime state is available.")
        }
        return
      }
      guard let versions = Self.commandOutput(
        at: bundledCLIURL,
        arguments: ["app-server", "daemon", "version"]
      ), Self.daemonVersionsMatch(versions)
      else {
        let adoptionFailure = self.compatibilityAdapter.prepare(
          bundledCLIURL: bundledCLIURL,
          cliVersion: cliVersion
        )
        DispatchQueue.main.async {
          self.connectionAttemptFailed(adoptionFailure ?? "The shared daemon was prepared after its existing control socket failed validation. Fully quit and reopen Codex Desktop; Beacon will reconnect automatically when shared runtime state is available.")
        }
        return
      }
      DispatchQueue.main.async {
        self.connectionAttemptInFlight = false
        guard !self.isStopped else { return }
        self.connect()
      }
    }
  }

  private func connectionAttemptFailed(_ reason: String) {
    connectionAttemptInFlight = false
    fail(reason)
  }

  private func connect() {
    guard !isStopped else { return }
    connectionGeneration += 1
    let generation = connectionGeneration
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
      fail("The shared App Server sent invalid JSON.")
      return
    }

    if !didInitialize {
      guard object["id"] as? Int == 1, object["error"] == nil else {
        fail("The shared App Server rejected passive initialization.")
        return
      }
      didInitialize = true
      client?.send(["method": "initialized"])
      deliver(.monitoringConnectionEstablished(protocolCompatible: true))
      flushRequests()
      DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
        guard
          let self,
          generation == self.connectionGeneration,
          self.didInitialize,
          !self.sawSharedDesktopRuntime
        else { return }
        self.fail("No loaded Codex Desktop runtime thread was observed. The reachable daemon is not accepted as shared Desktop state.")
      }
      return
    }

    // A request from the server intentionally has no response. Beacon is an
    // observer and must not take ownership of Desktop approvals or input.
    if object["id"] != nil, object["method"] != nil {
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
      sawSharedDesktopRuntime = true
      reconnectBackoff.recordSuccessfulConnection()
      compatibilityAdapter.sharedRuntimeEvidenceObserved()
      hasSharedDesktopRuntime = true
    } else {
      hasSharedDesktopRuntime = false
    }

    deliver(.appServerMessage(message))
    if hasSharedDesktopRuntime {
      deliver(.monitoringRuntimeValidated)
    }
    flushRequests()
  }

  private func connectionFailed(_ reason: String, from generation: Int) {
    guard !isStopped, generation == connectionGeneration else { return }
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
      client?.send(["id": request.id, "method": request.method, "params": params])
    }
  }

  private func fail(_ reason: String) {
    guard !isStopped else { return }
    connectionGeneration += 1
    diagnostic = reason
    diagnosticStore.record(reason)
    Logger(subsystem: "com.codexbeacon", category: "task-monitoring").error("\(reason, privacy: .public)")
    client?.close()
    client = nil
    didInitialize = false
    sawSharedDesktopRuntime = false
    deliver(.monitoringConnectionFailed)
    scheduleReconnect()
  }

  private func scheduleReconnect() {
    guard !isStopped, retryWorkItem == nil else {
      return
    }
    let delay = reconnectBackoff.nextDelayAfterFailure()
    let workItem = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.retryWorkItem = nil
      self.attemptConnection()
    }
    retryWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
  }

  private static let defaultSocketPath =
    (FileManager.default.homeDirectoryForCurrentUser.path as NSString)
      .appendingPathComponent(".codex/app-server-control/app-server-control.sock")

  private static func findBundledCLI() -> URL? {
    let codexURL = URL(string: "codex://threads/new")
    let appURL = codexURL.flatMap { NSWorkspace.shared.urlForApplication(toOpen: $0) }
    let candidates = [
      appURL?.appendingPathComponent("Contents/Resources/codex"),
      URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex"),
    ].compactMap { $0 }
    return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
  }

  private static func commandOutput(at executable: URL, arguments: [String]) -> String? {
    let process = Process()
    let output = Pipe()
    process.executableURL = executable
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = output
    do {
      try process.run()
      process.waitUntilExit()
      guard process.terminationStatus == 0 else { return nil }
      return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    } catch {
      return nil
    }
  }

  private static func cliVersion(at executable: URL) -> String? {
    guard let output = commandOutput(at: executable, arguments: ["--version"]) else { return nil }
    return output.split(whereSeparator: { $0 == " " || $0 == "\n" }).last.map(String.init)
  }

  private static func daemonVersionsMatch(_ output: String) -> Bool {
    let expression = #"\d+\.\d+\.\d+(?:-[A-Za-z0-9.]+)?"#
    guard let regex = try? NSRegularExpression(pattern: expression) else { return false }
    let range = NSRange(output.startIndex..., in: output)
    let versions = regex.matches(in: output, range: range).compactMap {
      Range($0.range, in: output).map { String(output[$0]) }
    }
    return versions.count >= 2 && versions[0] == versions[1]
  }
}

private final class UnixWebSocketClient: @unchecked Sendable {
  private let socketPath: String
  private let received: (String) -> Void
  private let failed: (String) -> Void
  private var socket: FileHandle?
  private var buffer = Data()
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
    buffer.append(data)
    if !isUpgraded {
      guard let range = buffer.range(of: Data("\r\n\r\n".utf8)) else { return }
      let response = String(decoding: buffer[..<range.lowerBound], as: UTF8.self)
      guard response.hasPrefix("HTTP/1.1 101") else { reportFailure("The App Server rejected the WebSocket upgrade."); return }
      buffer.removeSubrange(..<range.upperBound)
      isUpgraded = true
      send(["id": 1, "method": "initialize", "params": [
        "clientInfo": ["name": "codex-beacon", "title": "Codex Beacon passive observer", "version": "0.1.0"],
        "capabilities": ["experimentalApi": true],
      ]])
    }
    while !buffer.isEmpty {
      let byteCountBeforeParsing = buffer.count
      if let message = nextTextMessage() {
        received(message)
      }
      guard buffer.count < byteCountBeforeParsing else { break }
    }
  }

  private func nextTextMessage() -> String? {
    guard buffer.count >= 2 else { return nil }
    let bytes = [UInt8](buffer)
    let opcode = bytes[0] & 0x0F
    var offset = 2
    var length = Int(bytes[1] & 0x7F)
    if length == 126 { guard bytes.count >= 4 else { return nil }; length = Int(bytes[2]) << 8 | Int(bytes[3]); offset = 4 }
    if length == 127 || bytes.count < offset + length { return nil }
    let payload = Data(bytes[offset..<(offset + length)])
    buffer.removeSubrange(..<(offset + length))
    if opcode == 0x8 { reportFailure("The shared App Server closed the WebSocket."); return nil }
    if opcode == 0x9 { sendFrame(opcode: 0xA, payload: payload); return nil }
    return opcode == 0x1 ? String(data: payload, encoding: .utf8) : nil
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
