import Foundation
import Testing

@testable import CodexBeaconCore

@MainActor
struct WaitingAndCompletionScenarioTests {
  @Test("waiting requests retain their first observed time until each task is resolved")
  func waitingRequestsRetainTheirFirstObservedTime() {
    let coordinator = AppCoordinator()
    let firstWait = Date(timeIntervalSince1970: 1_753_344_000)
    let laterWait = Date(timeIntervalSince1970: 1_753_344_060)

    coordinator.handle(.time(.advanced(to: firstWait)))
    establishSnapshot(
      for: coordinator,
      threads: [
        "input": .waitingOnUserInput,
        "working": .working,
      ]
    )

    #expect(coordinator.viewState.status == .waitingForYou)
    #expect(
      coordinator.viewState.waitingTasks == [
        .init(threadID: "input", firstObservedAt: firstWait)
      ]
    )

    coordinator.handle(.time(.advanced(to: laterWait)))
    sendStatus(.working, for: "input", to: coordinator)

    #expect(coordinator.viewState.status == .working)
    #expect(coordinator.viewState.waitingTasks.isEmpty)

    sendStatus(.waitingOnApproval, for: "working", to: coordinator)

    #expect(coordinator.viewState.status == .waitingForYou)
    #expect(
      coordinator.viewState.waitingTasks == [
        .init(threadID: "working", firstObservedAt: laterWait)
      ]
    )

    coordinator.handle(.time(.advanced(to: laterWait.addingTimeInterval(60))))
    sendStatus(.waitingOnApproval, for: "working", to: coordinator)

    #expect(
      coordinator.viewState.waitingTasks == [
        .init(threadID: "working", firstObservedAt: laterWait)
      ]
    )
  }

  @Test("only successful terminal turns create process-local completion attention")
  func successfulTerminalTurnsCreateProcessLocalCompletionAttention() {
    let coordinator = AppCoordinator()

    establishSnapshot(
      for: coordinator,
      threads: [
        "succeeds": .working,
        "fails": .working,
        "interrupts": .working,
        "cancels": .working,
      ]
    )

    for threadID in ["succeeds", "fails", "interrupts", "cancels"] {
      sendStatus(.idle, for: threadID, to: coordinator)
    }

    for request in coordinator.drainAppServerRequests() {
      let turnStatus: String
      switch request.threadID {
      case "succeeds":
        turnStatus = "completed"
      case "fails":
        turnStatus = "failed"
      case "interrupts":
        turnStatus = "interrupted"
      case "cancels":
        turnStatus = "cancelled"
      default:
        Issue.record("unexpected latest-turn request")
        continue
      }
      coordinator.handle(
        .task(
          .appServerMessage(
            """
            {"id":\(request.id),"result":{"data":[{"id":"turn-\(request.threadID!)","status":"\(turnStatus)"}]}}
            """
          )
        )
      )
    }

    #expect(coordinator.viewState.status == .completed)
    #expect(coordinator.viewState.unconfirmedCompletionTaskIDs == ["succeeds"])

    establishSnapshot(for: coordinator, threads: ["succeeds": .idle])

    #expect(coordinator.viewState.status == .completed)
    #expect(coordinator.viewState.unconfirmedCompletionTaskIDs == ["succeeds"])

    coordinator.handle(.user(.beaconActivated))

    #expect(coordinator.viewState.status == .idle)
    #expect(coordinator.viewState.unconfirmedCompletionTaskIDs.isEmpty)
    #expect(coordinator.drainEffects() == [.activateCodex(threadID: "succeeds")])

    let afterRestart = AppCoordinator()
    establishSnapshot(for: afterRestart, threads: ["succeeds": .idle])

    #expect(afterRestart.viewState.status == .idle)
    #expect(afterRestart.viewState.unconfirmedCompletionTaskIDs.isEmpty)
  }

  @Test("failed and interrupted terminal turns leave no completion attention")
  func unsuccessfulTerminalTurnsLeaveNoCompletionAttention() {
    let coordinator = AppCoordinator()

    establishSnapshot(
      for: coordinator,
      threads: ["fails": .working, "interrupts": .working]
    )
    for threadID in ["fails", "interrupts"] {
      sendStatus(.idle, for: threadID, to: coordinator)
    }
    for request in coordinator.drainAppServerRequests() {
      let turnStatus = request.threadID == "fails" ? "failed" : "interrupted"
      coordinator.handle(
        .task(
          .appServerMessage(
            """
            {"id":\(request.id),"result":{"data":[{"id":"turn-\(request.threadID!)","status":"\(turnStatus)"}]}}
            """
          )
        )
      )
    }

    #expect(coordinator.viewState.status == .idle)
    #expect(coordinator.viewState.unconfirmedCompletionTaskIDs.isEmpty)
  }

  private func establishSnapshot(
    for coordinator: AppCoordinator,
    threads: [String: RuntimeState]
  ) {
    coordinator.handle(
      .task(.monitoringConnectionEstablished(protocolCompatible: true))
    )
    let loadedThreadsRequest = coordinator.drainAppServerRequests().first!
    let threadIDs = threads.keys.sorted()
    let encodedThreadIDs = threadIDs.map { "\"\($0)\"" }.joined(separator: ",")
    coordinator.handle(
      .task(
        .appServerMessage(
          """
          {"id":\(loadedThreadsRequest.id),"result":{"data":[\(encodedThreadIDs)]}}
          """
        )
      )
    )

    for request in coordinator.drainAppServerRequests() {
      guard let threadID = request.threadID, let state = threads[threadID] else {
        Issue.record("unexpected thread read request")
        continue
      }
      coordinator.handle(
        .task(
          .appServerMessage(
            """
            {"id":\(request.id),"result":{"thread":{"id":"\(threadID)","source":"vscode","ephemeral":false,"parentThreadId":null,"status":\(state.json)}}}
            """
          )
        )
      )
    }
  }

  private func sendStatus(
    _ state: RuntimeState,
    for threadID: String,
    to coordinator: AppCoordinator
  ) {
    coordinator.handle(
      .task(
        .appServerMessage(
          """
          {"method":"thread/status/changed","params":{"threadId":"\(threadID)","status":\(state.json)}}
          """
        )
      )
    )
  }
}

private enum RuntimeState {
  case idle
  case working
  case waitingOnApproval
  case waitingOnUserInput

  var json: String {
    switch self {
    case .idle:
      #"{"type":"idle"}"#
    case .working:
      #"{"type":"active","activeFlags":[]}"#
    case .waitingOnApproval:
      #"{"type":"active","activeFlags":["waitingOnApproval"]}"#
    case .waitingOnUserInput:
      #"{"type":"active","activeFlags":["waitingOnUserInput"]}"#
    }
  }
}
