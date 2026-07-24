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
          #""source":"subAgent","ephemeral":false,"parentThreadId":"visible-idle""#
      default:
        Issue.record("unexpected thread read request")
        continue
      }

      let status =
        request.threadID == "visible-idle"
        ? #"{"type":"idle"}"#
        : #"{"type":"active","activeFlags":[]}"#
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

    #expect(coordinator.viewState.status == .idle)
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
      coordinator.handle(.task(.noActiveTasksObserved))
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
}
