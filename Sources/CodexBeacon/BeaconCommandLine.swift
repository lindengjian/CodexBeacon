enum BeaconProcessCommand: Equatable {
  case launch
  case rollbackSharedDaemon
  case prepareForUninstall
}

enum BeaconCommandLine {
  static func command(arguments: [String]) -> BeaconProcessCommand {
    if arguments.contains("--prepare-for-uninstall") {
      return .prepareForUninstall
    }
    if arguments.contains("--rollback-shared-daemon") {
      return .rollbackSharedDaemon
    }
    return .launch
  }
}
