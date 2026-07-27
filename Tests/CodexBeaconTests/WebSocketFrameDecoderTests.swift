import Foundation
import Testing

@testable import CodexBeacon

struct WebSocketFrameDecoderTests {
  @Test("an extended-length notification does not block the following task status")
  func extendedLengthFrameDoesNotBlockFollowingTaskStatus() {
    let unrelatedNotification = Data(repeating: 0x61, count: 70_000)
    let taskStatus = Data(
      #"{"method":"thread/status/changed","params":{"threadId":"working-task","status":{"type":"active","activeFlags":[]}}}"#
        .utf8
    )
    var decoder = WebSocketFrameDecoder()
    decoder.append(serverTextFrame(unrelatedNotification))
    decoder.append(serverTextFrame(taskStatus))

    let firstFrame = decoder.nextFrame()
    let secondFrame = decoder.nextFrame()

    #expect(firstFrame?.opcode == 0x1)
    #expect(firstFrame?.payload == unrelatedNotification)
    #expect(secondFrame?.opcode == 0x1)
    #expect(secondFrame?.payload == taskStatus)
  }

  private func serverTextFrame(_ payload: Data) -> Data {
    var frame = Data([0x81, 127])
    let length = UInt64(payload.count)
    for shift in stride(from: 56, through: 0, by: -8) {
      frame.append(UInt8((length >> UInt64(shift)) & 0xFF))
    }
    frame.append(payload)
    return frame
  }
}
