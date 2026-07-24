import Testing

@testable import CodexBeaconCore

struct BeaconGeometryTests {
  @Test("standard Beacon uses the specified vertical dimensions")
  func standardBeaconDimensions() {
    #expect(BeaconSize.standard.dimensions == .init(width: 62, height: 229))
  }
}
