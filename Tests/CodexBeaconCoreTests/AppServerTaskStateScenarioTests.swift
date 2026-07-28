import Foundation
import Testing

@testable import CodexBeaconCore

@MainActor
struct AppServerTaskStateScenarioTests {
  @Test("an initial App Server snapshot presents a visible root task as working")
  func initialSnapshotPresentsWorkingTask() {
    let coordinator = AppCoordinator()

    coordinator.handle(
      .task(.monitoringConnectionEstablished(protocolCompatible: true))
    )
    let loadedListRequest = coordinator.drainAppServerRequests().first

    #expect(loadedListRequest?.method == "thread/loaded/list")

    coordinator.handle(
      .task(
        .appServerMessage(
          """
          {"id":\(loadedListRequest!.id),"result":{"data":["thread-1"]}}
          """
        )
      )
    )
    let threadReadRequest = coordinator.drainAppServerRequests().first

    #expect(threadReadRequest?.method == "thread/read")
    #expect(threadReadRequest?.threadID == "thread-1")

    coordinator.handle(
      .task(
        .appServerMessage(
          """
          {
            "id": \(threadReadRequest!.id),
            "result": {
              "thread": {
                "id": "thread-1",
                "source": "vscode",
                "ephemeral": false,
                "parentThreadId": null,
                "status": {"type": "active", "activeFlags": []}
              }
            }
          }
          """
        )
      )
    )

    #expect(coordinator.viewState.status == .working)
    #expect(
      coordinator.viewState.lights
        == [
          .init(color: .red, illumination: .off, showsRecess: true),
          .init(color: .amber, illumination: .steady, showsRecess: true),
          .init(color: .green, illumination: .off, showsRecess: true),
        ]
    )
  }

  @Test("an ephemeral Desktop user thread is presented as working")
  func ephemeralDesktopUserThreadPresentsWorkingTask() {
    let coordinator = AppCoordinator()

    coordinator.handle(
      .task(.monitoringConnectionEstablished(protocolCompatible: true))
    )
    let loadedListRequest = coordinator.drainAppServerRequests().first!
    coordinator.handle(
      .task(
        .appServerMessage(
          """
          {"id":\(loadedListRequest.id),"result":{"data":["new-user-thread"]}}
          """
        )
      )
    )
    let threadReadRequest = coordinator.drainAppServerRequests().first!

    coordinator.handle(
      .task(
        .appServerMessage(
          """
          {
            "id": \(threadReadRequest.id),
            "result": {
              "thread": {
                "id": "new-user-thread",
                "source": "vscode",
                "threadSource": "user",
                "ephemeral": true,
                "parentThreadId": null,
                "status": {"type": "active", "activeFlags": []}
              }
            }
          }
          """
        )
      )
    )

    #expect(coordinator.viewState.status == .working)
    #expect(coordinator.viewState.lights[1].illumination == .steady)
  }

  @Test("the aggregate excludes ephemeral, system, and child threads")
  func initialSnapshotFiltersNonRootTasks() {
    let coordinator = AppCoordinator()

    coordinator.handle(
      .task(.monitoringConnectionEstablished(protocolCompatible: true))
    )
    let loadedListRequest = coordinator.drainAppServerRequests().first!
    coordinator.handle(
      .task(
        .appServerMessage(
          """
          {
            "id": \(loadedListRequest.id),
            "result": {
              "data": ["visible-idle", "ephemeral", "system", "child"]
            }
          }
          """
        )
      )
    )

    let readRequests = coordinator.drainAppServerRequests()
    #expect(readRequests.map(\.method) == Array(repeating: "thread/read", count: 4))
    #expect(!readRequests.map(\.method).contains("thread/resume"))

    for request in readRequests {
      let classification: String
      switch request.threadID {
      case "visible-idle":
        classification =
          #""source":"vscode","ephemeral":false,"parentThreadId":null"#
      case "ephemeral":
        classification =
          #""source":"vscode","ephemeral":true,"parentThreadId":null"#
      case "system":
        classification =
          #""source":"vscode","threadSource":"system","ephemeral":false,"parentThreadId":null"#
      case "child":
        classification =
          #""source":{"subAgent":{"thread_spawn":{"parent_thread_id":"visible-idle"}}},"ephemeral":false,"parentThreadId":"visible-idle""#
      default:
        Issue.record("unexpected thread read request")
        continue
      }

      let status: String
      switch request.threadID {
      case "visible-idle":
        status = #"{"type":"idle"}"#
      case "system":
        status = #"{"type":"notLoaded"}"#
      default:
        status = #"{"type":"active","activeFlags":[]}"#
      }
      coordinator.handle(
        .task(
          .appServerMessage(
            """
            {
              "id": \(request.id),
              "result": {
                "thread": {
                  "id": "\(request.threadID!)",
                  \(classification),
                  "status": \(status)
                }
              }
            }
            """
          )
        )
      )
    }

    #expect(coordinator.viewState.status == .idle)
  }

  @Test("thread status notifications update the aggregate after the snapshot")
  func statusNotificationUpdatesAggregate() {
    let coordinator = AppCoordinator()

    coordinator.handle(
      .task(.monitoringConnectionEstablished(protocolCompatible: true))
    )
    let loadedListRequest = coordinator.drainAppServerRequests().first!
    coordinator.handle(
      .task(
        .appServerMessage(
          """
          {"id":\(loadedListRequest.id),"result":{"data":["thread-1"]}}
          """
        )
      )
    )
    let readRequest = coordinator.drainAppServerRequests().first!
    coordinator.handle(
      .task(
        .appServerMessage(
          """
          {
            "id": \(readRequest.id),
            "result": {
              "thread": {
                "id": "thread-1",
                "source": "vscode",
                "ephemeral": false,
                "parentThreadId": null,
                "status": {"type": "active", "activeFlags": []}
              }
            }
          }
          """
        )
      )
    )
    #expect(coordinator.viewState.status == .working)

    coordinator.handle(
      .task(
        .appServerMessage(
          """
          {
            "method": "thread/status/changed",
            "params": {
              "threadId": "thread-1",
              "status": {"type": "idle"}
            }
          }
          """
        )
      )
    )

    let latestTurnRequest = coordinator.drainAppServerRequests().first
    #expect(latestTurnRequest?.method == "thread/turns/list")
    #expect(latestTurnRequest?.threadID == "thread-1")

    coordinator.handle(
      .task(
        .appServerMessage(
          """
          {
            "id": \(latestTurnRequest!.id),
            "result": {"data": [{"id": "turn-1", "status": "completed"}]}
          }
          """
        )
      )
    )

    #expect(coordinator.viewState.status == .completed)
  }

  @Test("approval and user-input flags present waiting without replying to the server")
  func waitingFlagsPresentWaitingWithoutServerResponse() {
    let coordinator = AppCoordinator()

    coordinator.handle(
      .task(.monitoringConnectionEstablished(protocolCompatible: true))
    )
    let loadedListRequest = coordinator.drainAppServerRequests().first!
    coordinator.handle(
      .task(
        .appServerMessage(
          """
          {"id":\(loadedListRequest.id),"result":{"data":["thread-1"]}}
          """
        )
      )
    )
    let readRequest = coordinator.drainAppServerRequests().first!
    coordinator.handle(
      .task(
        .appServerMessage(
          """
          {
            "id": \(readRequest.id),
            "result": {
              "thread": {
                "id": "thread-1",
                "source": "vscode",
                "ephemeral": false,
                "parentThreadId": null,
                "status": {"type": "active", "activeFlags": ["waitingOnUserInput"]}
              }
            }
          }
          """
        )
      )
    )

    #expect(coordinator.viewState.status == .waitingForYou)

    coordinator.handle(
      .task(
        .appServerMessage(
          """
          {"id": 99, "method": "item/commandExecution/requestApproval", "params": {}}
          """
        )
      )
    )

    #expect(coordinator.viewState.status == .waitingForYou)
    #expect(coordinator.drainAppServerRequests().isEmpty)
  }

  @Test("connection, compatibility, and freshness failures are unavailable")
  func monitoringFailuresAreUnavailable() {
    let events: [TaskEvent] = [
      .monitoringConnectionFailed,
      .monitoringConnectionEstablished(protocolCompatible: false),
      .monitoringObservationBecameStale,
    ]

    for event in events {
      let coordinator = AppCoordinator()

      coordinator.handle(.task(event))

      #expect(coordinator.viewState.status == .monitoringUnavailable)
      #expect(
        coordinator.viewState.lights
          == [
            .init(color: .red, illumination: .steady, showsRecess: true),
            .init(color: .amber, illumination: .off, showsRecess: true),
            .init(color: .green, illumination: .off, showsRecess: true),
          ]
      )
    }
  }

  @Test("an incomplete initial snapshot remains unavailable")
  func incompleteSnapshotIsUnavailable() {
    let coordinator = AppCoordinator()

    coordinator.handle(
      .task(.monitoringConnectionEstablished(protocolCompatible: true))
    )

    #expect(coordinator.viewState.status == .monitoringUnavailable)

    let loadedListRequest = coordinator.drainAppServerRequests().first!
    coordinator.handle(
      .task(
        .appServerMessage(
          """
          {
            "id": \(loadedListRequest.id),
            "result": {"data": ["thread-1", "thread-2"]}
          }
          """
        )
      )
    )
    let readRequests = coordinator.drainAppServerRequests()
    let firstRead = readRequests[0]
    coordinator.handle(
      .task(
        .appServerMessage(
          """
          {
            "id": \(firstRead.id),
            "result": {
              "thread": {
                "id": "\(firstRead.threadID!)",
                "source": "vscode",
                "ephemeral": false,
                "parentThreadId": null,
                "status": {"type": "idle"}
              }
            }
          }
          """
        )
      )
    )

    #expect(coordinator.viewState.status == .monitoringUnavailable)
  }

  @Test("a loaded thread without current runtime evidence is unavailable")
  func notLoadedThreadIsUnavailable() {
    let coordinator = AppCoordinator()

    coordinator.handle(
      .task(.monitoringConnectionEstablished(protocolCompatible: true))
    )
    let loadedListRequest = coordinator.drainAppServerRequests().first!
    coordinator.handle(
      .task(
        .appServerMessage(
          """
          {"id":\(loadedListRequest.id),"result":{"data":["thread-1"]}}
          """
        )
      )
    )
    let readRequest = coordinator.drainAppServerRequests().first!
    coordinator.handle(
      .task(
        .appServerMessage(
          """
          {
            "id": \(readRequest.id),
            "result": {
              "thread": {
                "id": "thread-1",
                "source": "vscode",
                "ephemeral": false,
                "parentThreadId": null,
                "status": {"type": "notLoaded"}
              }
            }
          }
          """
        )
      )
    )

    #expect(coordinator.viewState.status == .monitoringUnavailable)
  }

  @Test("unavailable outranks working across multiple tasks")
  func unavailableOutranksWorking() {
    let coordinator = AppCoordinator()

    coordinator.handle(
      .task(.monitoringConnectionEstablished(protocolCompatible: true))
    )
    let loadedListRequest = coordinator.drainAppServerRequests().first!
    coordinator.handle(
      .task(
        .appServerMessage(
          """
          {
            "id": \(loadedListRequest.id),
            "result": {"data": ["working-thread", "idle-thread"]}
          }
          """
        )
      )
    )
    let readRequests = coordinator.drainAppServerRequests()

    for request in readRequests {
      let status =
        request.threadID == "working-thread"
        ? #"{"type":"active","activeFlags":[]}"#
        : #"{"type":"idle"}"#
      coordinator.handle(
        .task(
          .appServerMessage(
            """
            {
              "id": \(request.id),
              "result": {
                "thread": {
                  "id": "\(request.threadID!)",
                  "source": "vscode",
                  "ephemeral": false,
                  "parentThreadId": null,
                  "status": \(status)
                }
              }
            }
            """
          )
        )
      )
    }

    #expect(coordinator.viewState.status == .working)
    coordinator.handle(.task(.monitoringObservationBecameStale))
    #expect(coordinator.viewState.status == .monitoringUnavailable)
    coordinator.handle(
      .task(
        .appServerMessage(
          """
          {
            "method": "thread/status/changed",
            "params": {
              "threadId": "working-thread",
              "status": {"type": "active", "activeFlags": []}
            }
          }
          """
        )
      )
    )
    #expect(coordinator.viewState.status == .monitoringUnavailable)
    #expect(!readRequests.map(\.method).contains("thread/resume"))
  }

  @Test("an unknown changed thread is classified before entering the aggregate")
  func unknownChangedThreadIsReadBeforeAggregation() {
    let coordinator = AppCoordinator()

    coordinator.handle(
      .task(.monitoringConnectionEstablished(protocolCompatible: true))
    )
    let loadedListRequest = coordinator.drainAppServerRequests().first!
    coordinator.handle(
      .task(
        .appServerMessage(
          """
          {"id":\(loadedListRequest.id),"result":{"data":[]}}
          """
        )
      )
    )
    #expect(coordinator.viewState.status == .idle)

    coordinator.handle(
      .task(
        .appServerMessage(
          """
          {
            "method": "thread/status/changed",
            "params": {
              "threadId": "new-thread",
              "status": {"type": "active", "activeFlags": []}
            }
          }
          """
        )
      )
    )

    #expect(coordinator.viewState.status == .monitoringUnavailable)
    let readRequest = coordinator.drainAppServerRequests().first
    #expect(readRequest?.method == "thread/read")
    #expect(readRequest?.threadID == "new-thread")

    coordinator.handle(
      .task(
        .appServerMessage(
          """
          {
            "id": \(readRequest!.id),
            "result": {
              "thread": {
                "id": "new-thread",
                "source": "vscode",
                "ephemeral": false,
                "parentThreadId": null,
                "status": {"type": "active", "activeFlags": []}
              }
            }
          }
          """
        )
      )
    )

    #expect(coordinator.viewState.status == .working)
  }

  @Test("an unknown not-loaded thread notification does not invalidate monitoring")
  func unknownNotLoadedThreadDoesNotInvalidateMonitoring() {
    let coordinator = AppCoordinator()

    coordinator.handle(
      .task(.monitoringConnectionEstablished(protocolCompatible: true))
    )
    let loadedListRequest = coordinator.drainAppServerRequests().first!
    coordinator.handle(
      .task(
        .appServerMessage(
          """
          {"id":\(loadedListRequest.id),"result":{"data":[]}}
          """
        )
      )
    )
    #expect(coordinator.viewState.status == .idle)

    coordinator.handle(
      .task(
        .appServerMessage(
          """
          {
            "method": "thread/status/changed",
            "params": {
              "threadId": "internal-thread",
              "status": {"type": "notLoaded"}
            }
          }
          """
        )
      )
    )

    #expect(coordinator.viewState.status == .idle)
    #expect(coordinator.drainAppServerRequests().isEmpty)
  }

  @Test("a known task retains its last state while a not-loaded notification is refreshed")
  func knownTaskRetainsStateDuringNotLoadedRefresh() {
    let coordinator = AppCoordinator()

    coordinator.handle(
      .task(.monitoringConnectionEstablished(protocolCompatible: true))
    )
    let loadedListRequest = coordinator.drainAppServerRequests().first!
    coordinator.handle(
      .task(
        .appServerMessage(
          """
          {"id":\(loadedListRequest.id),"result":{"data":["visible-thread"]}}
          """
        )
      )
    )
    let initialReadRequest = coordinator.drainAppServerRequests().first!
    coordinator.handle(
      .task(
        .appServerMessage(
          """
          {
            "id": \(initialReadRequest.id),
            "result": {
              "thread": {
                "id": "visible-thread",
                "source": "vscode",
                "ephemeral": false,
                "parentThreadId": null,
                "status": {"type": "active", "activeFlags": []}
              }
            }
          }
          """
        )
      )
    )
    #expect(coordinator.viewState.status == .working)

    coordinator.handle(
      .task(
        .appServerMessage(
          """
          {
            "method": "thread/status/changed",
            "params": {
              "threadId": "visible-thread",
              "status": {"type": "notLoaded"}
            }
          }
          """
        )
      )
    )

    #expect(coordinator.viewState.status == .working)
    let refreshRequest = coordinator.drainAppServerRequests().first
    #expect(refreshRequest?.method == "thread/read")
    #expect(refreshRequest?.threadID == "visible-thread")

    coordinator.handle(
      .task(
        .appServerMessage(
          """
          {
            "id": \(refreshRequest!.id),
            "result": {
              "thread": {
                "id": "visible-thread",
                "source": "vscode",
                "ephemeral": false,
                "parentThreadId": null,
                "status": {"type": "notLoaded"}
              }
            }
          }
          """
        )
      )
    )
    #expect(coordinator.viewState.status == .working)
  }

  @Test("a periodic snapshot discovers a working task after its status notification is missed")
  func periodicSnapshotDiscoversWorkingTaskAfterMissedNotification() {
    let coordinator = AppCoordinator()

    coordinator.handle(
      .task(.monitoringConnectionEstablished(protocolCompatible: true))
    )
    let initialSnapshotRequest = coordinator.drainAppServerRequests().first!
    coordinator.handle(
      .task(
        .appServerMessage(
          """
          {"id":\(initialSnapshotRequest.id),"result":{"data":[]}}
          """
        )
      )
    )
    #expect(coordinator.viewState.status == .idle)

    coordinator.handle(.task(.monitoringSnapshotRequested))

    let refreshRequest = coordinator.drainAppServerRequests().first
    #expect(refreshRequest?.method == "thread/loaded/list")

    coordinator.handle(
      .task(
        .appServerMessage(
          """
          {"id":\(refreshRequest!.id),"result":{"data":["new-working-thread"]}}
          """
        )
      )
    )
    let threadReadRequest = coordinator.drainAppServerRequests().first
    #expect(threadReadRequest?.method == "thread/read")
    #expect(threadReadRequest?.threadID == "new-working-thread")

    coordinator.handle(.task(.monitoringSnapshotRequested))
    #expect(coordinator.drainAppServerRequests().isEmpty)

    coordinator.handle(
      .task(
        .appServerMessage(
          """
          {
            "id": \(threadReadRequest!.id),
            "result": {
              "thread": {
                "id": "new-working-thread",
                "source": "vscode",
                "ephemeral": false,
                "parentThreadId": null,
                "status": {"type": "active", "activeFlags": []}
              }
            }
          }
          """
        )
      )
    )

    #expect(coordinator.viewState.status == .working)
    #expect(coordinator.viewState.lights[1].illumination == .steady)
  }

  @Test("a transient thread read error during a refresh retains the last known task state")
  func refreshThreadReadErrorRetainsLastKnownTaskState() {
    let coordinator = AppCoordinator()

    coordinator.handle(.task(.monitoringConnectionEstablished(protocolCompatible: true)))
    let initialListRequest = coordinator.drainAppServerRequests().first!
    coordinator.handle(
      .task(.appServerMessage("""
        {"id":\(initialListRequest.id),"result":{"data":["switching-thread"]}}
        """))
    )
    let initialReadRequest = coordinator.drainAppServerRequests().first!
    coordinator.handle(
      .task(.appServerMessage("""
        {"id":\(initialReadRequest.id),"result":{"thread":{"id":"switching-thread","source":"vscode","ephemeral":false,"parentThreadId":null,"status":{"type":"active","activeFlags":[]}}}}
        """))
    )
    #expect(coordinator.viewState.status == .working)

    coordinator.handle(.task(.monitoringSnapshotRequested))
    let refreshListRequest = coordinator.drainAppServerRequests().first!
    coordinator.handle(
      .task(.appServerMessage("""
        {"id":\(refreshListRequest.id),"result":{"data":["switching-thread"]}}
        """))
    )
    let refreshReadRequest = coordinator.drainAppServerRequests().first!

    coordinator.handle(
      .task(.appServerMessage("""
        {"id":\(refreshReadRequest.id),"error":{"message":"Thread is no longer loaded"}}
        """))
    )

    #expect(coordinator.viewState.status == .working)
    #expect(coordinator.viewState.lights[0].illumination == .off)
    #expect(coordinator.viewState.lights[1].illumination == .steady)
  }

  @Test("an initial thread read error is retried by the next snapshot")
  func initialThreadReadErrorRecoversOnNextSnapshot() {
    let coordinator = AppCoordinator()

    coordinator.handle(.task(.monitoringConnectionEstablished(protocolCompatible: true)))
    let initialListRequest = coordinator.drainAppServerRequests().first!
    coordinator.handle(
      .task(.appServerMessage("""
        {"id":\(initialListRequest.id),"result":{"data":["switching-thread"]}}
        """))
    )
    let initialReadRequest = coordinator.drainAppServerRequests().first!
    coordinator.handle(
      .task(.appServerMessage("""
        {"id":\(initialReadRequest.id),"error":{"message":"Thread is no longer loaded"}}
        """))
    )
    #expect(coordinator.viewState.status == .monitoringUnavailable)

    coordinator.handle(.task(.monitoringSnapshotRequested))
    let retryListRequest = coordinator.drainAppServerRequests().first
    #expect(retryListRequest?.method == "thread/loaded/list")

    coordinator.handle(
      .task(.appServerMessage("""
        {"id":\(retryListRequest!.id),"result":{"data":[]}}
        """))
    )

    #expect(coordinator.viewState.status == .idle)
    #expect(coordinator.viewState.lights[0].illumination == .off)
  }

  @Test("a missing thread read is retried after the snapshot timeout")
  func missingThreadReadRecoversAfterSnapshotTimeout() {
    let coordinator = AppCoordinator()
    let initialTime = Date(timeIntervalSince1970: 1_753_353_600)
    coordinator.handle(.time(.advanced(to: initialTime)))
    coordinator.handle(.task(.monitoringConnectionEstablished(protocolCompatible: true)))
    let loadedListRequest = coordinator.drainAppServerRequests().first!
    coordinator.handle(
      .task(.appServerMessage("""
        {"id":\(loadedListRequest.id),"result":{"data":["unresponsive-thread"]}}
        """))
    )
    let missingReadRequest = coordinator.drainAppServerRequests().first!
    #expect(missingReadRequest.method == "thread/read")

    coordinator.handle(
      .time(.advanced(to: initialTime.addingTimeInterval(7)))
    )
    coordinator.handle(.task(.monitoringSnapshotRequested))

    let retryRequest = coordinator.drainAppServerRequests().first!
    #expect(retryRequest.method == "thread/loaded/list")
    coordinator.handle(
      .task(.appServerMessage("""
        {"id":\(retryRequest.id),"result":{"data":["new-working-thread"]}}
        """))
    )
    let replacementReadRequest = coordinator.drainAppServerRequests().first!
    coordinator.handle(
      .task(.appServerMessage("""
        {"id":\(replacementReadRequest.id),"result":{"thread":{"id":"new-working-thread","source":"vscode","ephemeral":false,"parentThreadId":null,"status":{"type":"active","activeFlags":[]}}}}
        """))
    )

    #expect(coordinator.viewState.status == .working)
    #expect(coordinator.viewState.lights[1].illumination == .steady)
  }

  @Test("a progressing snapshot is not discarded while loaded threads arrive slowly")
  func progressingSnapshotDoesNotTimeOut() {
    let coordinator = AppCoordinator()
    let initialTime = Date(timeIntervalSince1970: 1_753_353_600)
    coordinator.handle(.time(.advanced(to: initialTime)))
    coordinator.handle(.task(.monitoringConnectionEstablished(protocolCompatible: true)))
    let loadedListRequest = coordinator.drainAppServerRequests().first!
    coordinator.handle(
      .task(.appServerMessage("""
        {"id":\(loadedListRequest.id),"result":{"data":["first-idle","second-idle","working-thread"]}}
        """))
    )
    let readRequests = Dictionary(
      uniqueKeysWithValues: coordinator.drainAppServerRequests().map { ($0.threadID!, $0) }
    )

    coordinator.handle(.time(.advanced(to: initialTime.addingTimeInterval(4))))
    coordinator.handle(
      .task(.appServerMessage("""
        {"id":\(readRequests["first-idle"]!.id),"result":{"thread":{"id":"first-idle","source":"vscode","ephemeral":false,"parentThreadId":null,"status":{"type":"idle"}}}}
        """))
    )

    coordinator.handle(.time(.advanced(to: initialTime.addingTimeInterval(7))))
    coordinator.handle(.task(.monitoringSnapshotRequested))
    #expect(coordinator.drainAppServerRequests().isEmpty)

    coordinator.handle(.time(.advanced(to: initialTime.addingTimeInterval(8))))
    coordinator.handle(
      .task(.appServerMessage("""
        {"id":\(readRequests["second-idle"]!.id),"result":{"thread":{"id":"second-idle","source":"vscode","ephemeral":false,"parentThreadId":null,"status":{"type":"idle"}}}}
        """))
    )
    coordinator.handle(.time(.advanced(to: initialTime.addingTimeInterval(12))))
    coordinator.handle(
      .task(.appServerMessage("""
        {"id":\(readRequests["working-thread"]!.id),"result":{"thread":{"id":"working-thread","source":"vscode","ephemeral":false,"parentThreadId":null,"status":{"type":"active","activeFlags":[]}}}}
        """))
    )

    #expect(coordinator.viewState.status == .working)
  }

  @Test("unrelated App Server notifications do not invalidate task evidence")
  func unrelatedNotificationDoesNotChangeAggregate() {
    let coordinator = AppCoordinator()

    coordinator.handle(
      .task(.monitoringConnectionEstablished(protocolCompatible: true))
    )
    let loadedListRequest = coordinator.drainAppServerRequests().first!
    coordinator.handle(
      .task(
        .appServerMessage(
          """
          {"id":\(loadedListRequest.id),"result":{"data":[]}}
          """
        )
      )
    )
    #expect(coordinator.viewState.status == .idle)

    coordinator.handle(
      .task(
        .appServerMessage(
          """
          {
            "method": "account/rateLimits/updated",
            "params": {"rateLimits": {}}
          }
          """
        )
      )
    )

    #expect(coordinator.viewState.status == .idle)
    #expect(coordinator.drainAppServerRequests().isEmpty)
  }
}
