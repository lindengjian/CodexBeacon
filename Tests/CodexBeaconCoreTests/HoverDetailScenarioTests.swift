import Foundation
import Testing

@testable import CodexBeaconCore

@MainActor
struct HoverDetailScenarioTests {
  @Test("hover detail is populated after start with monitoring unavailable status")
  func hoverDetailPopulatedAfterStart() throws {
    let coordinator = AppCoordinator()

    coordinator.start()

    let detail = try #require(coordinator.viewState.hoverDetail)
    #expect(detail.status == .monitoringUnavailable)
    #expect(detail.taskError == "任务监测不可用")
    #expect(detail.workingCount == 0)
    #expect(detail.waitingCount == 0)
    #expect(detail.completedCount == 0)
  }

  @Test("hover detail shows aggregate counts after snapshot with multiple tasks")
  func hoverDetailShowsAggregateCounts() throws {
    let coordinator = AppCoordinator()

    establishSnapshot(
      for: coordinator,
      threads: [
        "working-a": .working,
        "working-b": .working,
        "waiting": .waitingOnUserInput,
        "idle": .idle,
      ]
    )

    let detail = try #require(coordinator.viewState.hoverDetail)
    #expect(detail.workingCount == 2)
    #expect(detail.waitingCount == 1)
    #expect(detail.completedCount == 0)
    #expect(detail.status == .waitingForYou)
    #expect(detail.aggregateCountsDescription == "工作 2 · 等待你 1")
  }

  @Test("hover detail shows completed tasks in aggregate counts")
  func hoverDetailShowsCompletedCounts() throws {
    let coordinator = AppCoordinator()

    establishSnapshot(
      for: coordinator,
      threads: ["worker": .working]
    )

    sendStatus(.idle, for: "worker", to: coordinator)

    for request in coordinator.drainAppServerRequests() {
      coordinator.handle(
        .task(
          .appServerMessage(
            """
            {"id":\(request.id),"result":{"data":[{"id":"turn-1","status":"completed"}]}}
            """
          )
        )
      )
    }

    let detail = try #require(coordinator.viewState.hoverDetail)
    #expect(detail.completedCount == 1)
    #expect(detail.status == .completed)
    #expect(detail.aggregateCountsDescription == "完成 1")
  }

  @Test("hover detail shows all quota windows when available")
  func hoverDetailShowsQuotaWindows() throws {
    let coordinator = AppCoordinator()

    coordinator.handle(.task(.monitoringConnectionEstablished(protocolCompatible: true)))
    _ = coordinator.drainAppServerRequests()

    coordinator.handle(
      .task(
        .appServerMessage(
          """
          {"method":"account/rateLimits/updated","params":{"rateLimits":{"5m":{"usedPercent":40,"windowDurationMins":5},"1d":{"usedPercent":10,"windowDurationMins":1440}}}}
          """
        )
      )
    )

    let detail = try #require(coordinator.viewState.hoverDetail)
    #expect(detail.quotaWindows.count == 2)
    #expect(detail.quotaError == nil)
  }

  @Test("hover detail reports task error when monitoring is unavailable")
  func hoverDetailShowsTaskError() throws {
    let coordinator = AppCoordinator()

    coordinator.start()

    let detail = try #require(coordinator.viewState.hoverDetail)
    #expect(detail.taskError == "任务监测不可用")
  }

  @Test("show task titles defaults to false but titles still propagate in task entries")
  func showTaskTitlesDefaultsFalse() throws {
    let coordinator = AppCoordinator()

    establishSnapshot(
      for: coordinator,
      threads: ["t1": .working],
      titles: ["t1": "Fix the bug"]
    )

    let detail = try #require(coordinator.viewState.hoverDetail)
    #expect(!detail.showTaskTitles)
    #expect(coordinator.viewState.showTaskTitles == false)
    let task = try #require(detail.tasks.first)
    #expect(task.title == "Fix the bug")
  }

  @Test("enabling show task titles exposes titles in hover detail")
  func enableShowTaskTitles() throws {
    let coordinator = AppCoordinator(showTaskTitles: false)

    establishSnapshot(
      for: coordinator,
      threads: ["t1": .working],
      titles: ["t1": "Fix the bug"]
    )

    coordinator.setShowTaskTitles(true)

    let detail = try #require(coordinator.viewState.hoverDetail)
    #expect(detail.showTaskTitles)
    #expect(coordinator.viewState.showTaskTitles)

    let task = try #require(detail.tasks.first)
    #expect(task.title == "Fix the bug")
  }

  @Test("disabling show task titles does not clear titles from task entries")
  func disableShowTaskTitles() throws {
    let coordinator = AppCoordinator(showTaskTitles: true)

    establishSnapshot(
      for: coordinator,
      threads: ["t1": .working],
      titles: ["t1": "Fix the bug"]
    )

    coordinator.setShowTaskTitles(false)

    let detail = try #require(coordinator.viewState.hoverDetail)
    #expect(!detail.showTaskTitles)
    #expect(!coordinator.viewState.showTaskTitles)
    let task = try #require(detail.tasks.first)
    #expect(task.title == "Fix the bug")
  }

  @Test("hover detail tasks reflect waiting, working, and completed states")
  func hoverDetailTaskStates() throws {
    let coordinator = AppCoordinator()

    establishSnapshot(
      for: coordinator,
      threads: [
        "w1": .working,
        "wf1": .waitingOnApproval,
      ]
    )

    sendStatus(.idle, for: "w1", to: coordinator)

    for request in coordinator.drainAppServerRequests() {
      coordinator.handle(
        .task(
          .appServerMessage(
            """
            {"id":\(request.id),"result":{"data":[{"id":"turn-w1","status":"completed"}]}}
            """
          )
        )
      )
    }

    let detail = try #require(coordinator.viewState.hoverDetail)
    #expect(detail.tasks.contains(where: { $0.threadID == "w1" && $0.state == .completed }))
    #expect(detail.tasks.contains(where: { $0.threadID == "wf1" && $0.state == .waitingForYou }))
  }

  @Test("hover detail task entries carry sessionId from protocol thread response")
  func hoverDetailCarriesSessionId() throws {
    let coordinator = AppCoordinator()

    establishSnapshot(
      for: coordinator,
      threads: ["w1": .working, "wf1": .waitingOnApproval],
      titles: ["w1": "Fix the bug", "wf1": "Review PR"],
      sessionIds: ["w1": "sess-abc", "wf1": "sess-def"]
    )

    let detail = try #require(coordinator.viewState.hoverDetail)
    let workingTask = try #require(detail.tasks.first(where: { $0.threadID == "w1" }))
    #expect(workingTask.sessionId == "sess-abc")
    #expect(workingTask.title == "Fix the bug")
    let waitingTask = try #require(detail.tasks.first(where: { $0.threadID == "wf1" }))
    #expect(waitingTask.sessionId == "sess-def")
    #expect(waitingTask.title == "Review PR")
  }

  @Test("threadName from status notification captured as task title")
  func threadNameFromStatusNotification() throws {
    let coordinator = AppCoordinator(showTaskTitles: true)

    establishSnapshot(
      for: coordinator,
      threads: ["t1": .working],
      titles: ["t1": "Initial Title"]
    )

    // Status notification carries threadName; it should update the title
    sendStatus(.idle, for: "t1", to: coordinator, threadName: "Updated Name")

    for request in coordinator.drainAppServerRequests() {
      coordinator.handle(
        .task(
          .appServerMessage(
            """
            {"id":\(request.id),"result":{"data":[{"id":"turn-t1","status":"completed"}]}}
            """
          )
        )
      )
    }

    let detail = try #require(coordinator.viewState.hoverDetail)
    let task = try #require(detail.tasks.first(where: { $0.threadID == "t1" }))
    #expect(task.title == "Updated Name")
    #expect(task.state == .completed)
  }

  @Test("aggregate counts description omits zero counts")
  func aggregateCountsOmitsZeros() {
    let state = HoverDetailState(
      status: .working,
      workingCount: 3,
      waitingCount: 0,
      completedCount: 0,
      tasks: [],
      quotaWindows: [],
      lastUpdatedAt: nil,
      taskError: nil,
      quotaError: nil,
      showTaskTitles: false
    )

    #expect(state.aggregateCountsDescription == "工作 3")
  }

  @Test("aggregate counts description shows all non-zero counts")
  func aggregateCountsShowsAllNonZero() {
    let state = HoverDetailState(
      status: .working,
      workingCount: 1,
      waitingCount: 2,
      completedCount: 3,
      tasks: [],
      quotaWindows: [],
      lastUpdatedAt: nil,
      taskError: nil,
      quotaError: nil,
      showTaskTitles: false
    )

    #expect(state.aggregateCountsDescription == "工作 1 · 等待你 2 · 完成 3")
  }

  // MARK: - Helpers

  private func establishSnapshot(
    for coordinator: AppCoordinator,
    threads: [String: RuntimeState],
    titles: [String: String] = [:],
    sessionIds: [String: String] = [:]
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
      let titleJSON: String
      if let title = titles[threadID] {
        titleJSON = ",\"title\":\"\(title)\""
      } else {
        titleJSON = ""
      }
      let sessionIdJSON: String
      if let sessionId = sessionIds[threadID] {
        sessionIdJSON = ",\"sessionId\":\"\(sessionId)\""
      } else {
        sessionIdJSON = ""
      }
      coordinator.handle(
        .task(
          .appServerMessage(
            """
            {"id":\(request.id),"result":{"thread":{"id":"\(threadID)","source":"vscode","ephemeral":false,"parentThreadId":null,"status":\(state.json)\(titleJSON)\(sessionIdJSON)}}}
            """
          )
        )
      )
    }
  }

  private func sendStatus(
    _ state: RuntimeState,
    for threadID: String,
    to coordinator: AppCoordinator,
    threadName: String? = nil
  ) {
    let nameJSON: String
    if let threadName {
      nameJSON = ",\"threadName\":\"\(threadName)\""
    } else {
      nameJSON = ""
    }
    coordinator.handle(
      .task(
        .appServerMessage(
          """
          {"method":"thread/status/changed","params":{"threadId":"\(threadID)","status":\(state.json)\(nameJSON)}}
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
