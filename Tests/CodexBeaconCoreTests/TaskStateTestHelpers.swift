import Foundation
import Testing

@testable import CodexBeaconCore

enum TaskState {
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

@MainActor
func establishSnapshot(
  for coordinator: AppCoordinator,
  threads: [String: TaskState]
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

@MainActor
func sendStatus(
  _ state: TaskState,
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
