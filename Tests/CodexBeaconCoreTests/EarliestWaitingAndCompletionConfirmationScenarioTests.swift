import Foundation
import Testing

@testable import CodexBeaconCore

@MainActor
struct EarliestWaitingAndCompletionConfirmationScenarioTests {
  @Test("beacon activation selects the earliest waiting task for deep-link navigation")
  func beaconActivationSelectsEarliestWaitingTask() {
    let coordinator = AppCoordinator()
    let firstWait = Date(timeIntervalSince1970: 1_753_344_000)
    let secondWait = Date(timeIntervalSince1970: 1_753_344_060)

    coordinator.handle(.time(.advanced(to: firstWait)))
    establishSnapshot(
      for: coordinator,
      threads: ["later": .working, "earliest": .working]
    )

    coordinator.handle(.time(.advanced(to: secondWait)))
    sendStatus(.waitingOnUserInput, for: "later", to: coordinator)
    sendStatus(.waitingOnUserInput, for: "earliest", to: coordinator)

    #expect(coordinator.viewState.status == .waitingForYou)
    #expect(coordinator.viewState.waitingTasks.count == 2)
    #expect(coordinator.viewState.waitingTasks.first?.threadID == "earliest")

    coordinator.handle(.user(.beaconActivated))

    #expect(
      coordinator.drainEffects().contains(.activateCodex(threadID: "earliest"))
    )
  }

  @Test("beacon activation navigates to new thread route when no waiting tasks exist")
  func beaconActivationFallsBackToNewRouteWithoutWaitingTasks() {
    let coordinator = AppCoordinator()

    establishSnapshot(
      for: coordinator,
      threads: ["done": .idle]
    )

    coordinator.handle(.user(.beaconActivated))

    #expect(coordinator.viewState.status == .idle)
    #expect(
      coordinator.drainEffects().contains(.activateCodex(threadID: nil))
    )
  }

  @Test("beacon activation snapshots unconfirmed completions and confirms only those")
  func beaconActivationSnapshotsAndConfirmsCurrentCompletions() {
    let coordinator = AppCoordinator()

    establishSnapshot(
      for: coordinator,
      threads: ["task-a": .working, "task-b": .working]
    )

    for threadID in ["task-a", "task-b"] {
      sendStatus(.idle, for: threadID, to: coordinator)
    }
    for request in coordinator.drainAppServerRequests() {
      coordinator.handle(
        .task(
          .appServerMessage(
            """
            {"id":\(request.id),"result":{"data":[{"id":"turn-\(request.threadID!)","status":"completed"}]}}
            """
          )
        )
      )
    }

    #expect(coordinator.viewState.status == .completed)
    #expect(
      coordinator.viewState.unconfirmedCompletionTaskIDs
        == ["task-a", "task-b"]
    )

    coordinator.handle(.user(.beaconActivated))

    #expect(coordinator.viewState.unconfirmedCompletionTaskIDs.isEmpty)
    #expect(coordinator.viewState.status == .idle)

    let effects = coordinator.drainEffects()
    guard case .activateCodex(let threadID) = effects.first else {
      Issue.record("expected activateCodex effect")
      return
    }
    #expect(threadID != nil)
    #expect(["task-a", "task-b"].contains(threadID!))
  }

  @Test("new completions arriving after beacon activation are not pre-confirmed")
  func newCompletionsAfterActivationAreNotPreConfirmed() {
    let coordinator = AppCoordinator()

    establishSnapshot(
      for: coordinator,
      threads: ["task-a": .working, "task-b": .working]
    )

    sendStatus(.idle, for: "task-a", to: coordinator)
    for request in coordinator.drainAppServerRequests() {
      coordinator.handle(
        .task(
          .appServerMessage(
            """
            {"id":\(request.id),"result":{"data":[{"id":"turn-task-a","status":"completed"}]}}
            """
          )
        )
      )
    }

    #expect(
      coordinator.viewState.unconfirmedCompletionTaskIDs == ["task-a"]
    )

    coordinator.handle(.user(.beaconActivated))

    #expect(coordinator.viewState.unconfirmedCompletionTaskIDs.isEmpty)

    sendStatus(.idle, for: "task-b", to: coordinator)
    for request in coordinator.drainAppServerRequests() {
      coordinator.handle(
        .task(
          .appServerMessage(
            """
            {"id":\(request.id),"result":{"data":[{"id":"turn-task-b","status":"completed"}]}}
            """
          )
        )
      )
    }

    #expect(
      coordinator.viewState.unconfirmedCompletionTaskIDs == ["task-b"]
    )
    #expect(coordinator.viewState.status == .completed)
  }

  @Test("auto-confirm policy triggers confirmation for new completions")
  func autoConfirmConditionTriggersForNewCompletions() {
    let coordinator = AppCoordinator()
    coordinator.autoConfirmCondition = { true }

    establishSnapshot(
      for: coordinator,
      threads: ["task-a": .working]
    )

    sendStatus(.idle, for: "task-a", to: coordinator)
    for request in coordinator.drainAppServerRequests() {
      coordinator.handle(
        .task(
          .appServerMessage(
            """
            {"id":\(request.id),"result":{"data":[{"id":"turn-task-a","status":"completed"}]}}
            """
          )
        )
      )
    }

    #expect(coordinator.viewState.status == .idle)
    #expect(coordinator.viewState.unconfirmedCompletionTaskIDs.isEmpty)
  }

  @Test("auto-confirm policy rejection leaves completions unconfirmed")
  func autoConfirmConditionRejectionLeavesCompletionsUnconfirmed() {
    let coordinator = AppCoordinator()
    coordinator.autoConfirmCondition = { false }

    establishSnapshot(
      for: coordinator,
      threads: ["task-a": .working]
    )

    sendStatus(.idle, for: "task-a", to: coordinator)
    for request in coordinator.drainAppServerRequests() {
      coordinator.handle(
        .task(
          .appServerMessage(
            """
            {"id":\(request.id),"result":{"data":[{"id":"turn-task-a","status":"completed"}]}}
            """
          )
        )
      )
    }

    #expect(coordinator.viewState.status == .completed)
    #expect(
      coordinator.viewState.unconfirmedCompletionTaskIDs == ["task-a"]
    )
  }

  @Test("auto-confirm respects shared runtime validation gate")
  func autoConfirmRespectsSharedRuntimeValidationGate() {
    let coordinator = AppCoordinator(requiresSharedRuntimeEvidence: true)
    coordinator.autoConfirmCondition = { true }

    coordinator.handle(
      .task(.monitoringConnectionEstablished(protocolCompatible: true))
    )
    let loadedListRequest = coordinator.drainAppServerRequests().first!
    coordinator.handle(
      .task(
        .appServerMessage(
          """
          {"id":\(loadedListRequest.id),"result":{"data":["task-a"]}}
          """
        )
      )
    )
    let readRequest = coordinator.drainAppServerRequests().first!
    coordinator.handle(
      .task(
        .appServerMessage(
          """
          {"id":\(readRequest.id),"result":{"thread":{"id":"task-a","source":"vscode","ephemeral":false,"parentThreadId":null,"status":{"type":"active","activeFlags":[]}}}}
          """
        )
      )
    )

    #expect(coordinator.viewState.status == .monitoringUnavailable)

    sendStatus(.idle, for: "task-a", to: coordinator)
    for request in coordinator.drainAppServerRequests() {
      coordinator.handle(
        .task(
          .appServerMessage(
            """
            {"id":\(request.id),"result":{"data":[{"id":"turn-task-a","status":"completed"}]}}
            """
          )
        )
      )
    }

    #expect(coordinator.viewState.status == .monitoringUnavailable)
    #expect(
      coordinator.viewState.unconfirmedCompletionTaskIDs == ["task-a"]
    )

    coordinator.handle(.task(.monitoringRuntimeValidated))

    #expect(coordinator.viewState.status == .completed)
    #expect(
      coordinator.viewState.unconfirmedCompletionTaskIDs == ["task-a"]
    )
  }

  @Test("only the earliest waiting task is selected when multiple tasks wait")
  func onlyEarliestWaitingTaskSelectedFromMultiple() {
    let coordinator = AppCoordinator()
    let times: [String: Date] = [
      "third": Date(timeIntervalSince1970: 1_753_344_120),
      "first": Date(timeIntervalSince1970: 1_753_344_000),
      "second": Date(timeIntervalSince1970: 1_753_344_060),
    ]

    establishSnapshot(
      for: coordinator,
      threads: Dictionary(
        uniqueKeysWithValues: times.keys.map { ($0, TaskState.working) }
      )
    )

    for (threadID, time) in times {
      coordinator.handle(.time(.advanced(to: time)))
      sendStatus(.waitingOnApproval, for: threadID, to: coordinator)
    }

    #expect(coordinator.viewState.waitingTasks.map(\.threadID) == ["first", "second", "third"])

    coordinator.handle(.user(.beaconActivated))

    #expect(
      coordinator.drainEffects().contains(.activateCodex(threadID: "first"))
    )
  }

  @Test("confirming completions while tasks still working transitions to working status")
  func confirmingCompletionsWhileTasksStillWorking() {
    let coordinator = AppCoordinator()

    establishSnapshot(
      for: coordinator,
      threads: ["completed": .working, "still-working": .working]
    )

    sendStatus(.idle, for: "completed", to: coordinator)
    for request in coordinator.drainAppServerRequests() {
      coordinator.handle(
        .task(
          .appServerMessage(
            """
            {"id":\(request.id),"result":{"data":[{"id":"turn-completed","status":"completed"}]}}
            """
          )
        )
      )
    }

    #expect(coordinator.viewState.status == .working)

    coordinator.handle(.user(.beaconActivated))

    #expect(coordinator.viewState.status == .working)
    #expect(coordinator.viewState.unconfirmedCompletionTaskIDs.isEmpty)
  }

  @Test("beacon activation navigates to the working task when amber light is on")
  func beaconActivationNavigatesToWorkingTask() {
    let coordinator = AppCoordinator()

    establishSnapshot(
      for: coordinator,
      threads: ["working-task": .working]
    )

    #expect(coordinator.viewState.status == .working)

    coordinator.handle(.user(.beaconActivated))

    #expect(
      coordinator.drainEffects().contains(.activateCodex(threadID: "working-task"))
    )
  }

  @Test("beacon activation navigates to the completed task when green light is on for completions")
  func beaconActivationNavigatesToCompletedTask() {
    let coordinator = AppCoordinator()

    establishSnapshot(
      for: coordinator,
      threads: ["done-task": .working]
    )

    sendStatus(.idle, for: "done-task", to: coordinator)
    for request in coordinator.drainAppServerRequests() {
      coordinator.handle(
        .task(
          .appServerMessage(
            """
            {"id":\(request.id),"result":{"data":[{"id":"turn-done-task","status":"completed"}]}}
            """
          )
        )
      )
    }

    #expect(coordinator.viewState.status == .completed)
    #expect(coordinator.viewState.unconfirmedCompletionTaskIDs == ["done-task"])

    coordinator.handle(.user(.beaconActivated))

    #expect(
      coordinator.drainEffects().contains(.activateCodex(threadID: "done-task"))
    )
    #expect(coordinator.viewState.unconfirmedCompletionTaskIDs.isEmpty)
  }

  @Test("beacon activation navigates to the earliest working task by observation order")
  func beaconActivationNavigatesToEarliestWorkingTask() {
    let coordinator = AppCoordinator()

    establishSnapshot(
      for: coordinator,
      threads: ["b-task": .working, "a-task": .working]
    )

    #expect(coordinator.viewState.status == .working)

    coordinator.handle(.user(.beaconActivated))

    #expect(
      coordinator.drainEffects().contains(.activateCodex(threadID: "a-task"))
    )
  }
}
