import Testing

@testable import CodexBeaconCore

struct MacPresentationContractTests {
  @Test("standard Beacon uses the non-activating accessory presentation contract")
  func standardBeaconPresentationContract() {
    let presentation = MacApplicationPresentation.beacon

    #expect(BeaconSize.standard.dimensions == .init(width: 62, height: 229))
    #expect(presentation.activationPolicy == .accessory)
    #expect(!presentation.createsDockIcon)
    #expect(!presentation.createsMenuBarItem)
    #expect(presentation.window.isNonActivating)
    #expect(presentation.window.level == .floating)
    #expect(presentation.window.appearsOnAllSpaces)
    #expect(presentation.window.appearsOverFullScreenApplications)
  }
}
