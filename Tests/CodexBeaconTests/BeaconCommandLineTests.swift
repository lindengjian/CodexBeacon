import Testing

@testable import CodexBeacon

struct BeaconCommandLineTests {
  @Test("launches the Beacon when no process command is supplied")
  func launchesByDefault() {
    #expect(BeaconCommandLine.command(arguments: ["CodexBeacon"]) == .launch)
  }

  @Test("keeps the shared-daemon rollback command available for recovery")
  func parsesRollbackCommand() {
    #expect(
      BeaconCommandLine.command(arguments: ["CodexBeacon", "--rollback-shared-daemon"])
        == .rollbackSharedDaemon
    )
  }

  @Test("prepares the installed app for removal without launching its UI")
  func parsesPrepareForUninstallCommand() {
    #expect(
      BeaconCommandLine.command(arguments: ["CodexBeacon", "--prepare-for-uninstall"])
        == .prepareForUninstall
    )
  }
}
