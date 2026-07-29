import AppKit
import CodexBeaconCore

switch BeaconCommandLine.command(arguments: CommandLine.arguments) {
case .rollbackSharedDaemon:
  DesktopDaemonCompatibilityAdapter().rollback()
  exit(EXIT_SUCCESS)
case .prepareForUninstall:
  BeaconSystemIntegration.unregisterLaunchAtLoginForUninstall()
  DesktopDaemonCompatibilityAdapter().rollback()
  exit(EXIT_SUCCESS)
case .launch:
  break
}

let application = NSApplication.shared
let applicationDelegate = BeaconAppDelegate()

application.setActivationPolicy(.accessory)
application.delegate = applicationDelegate
application.run()
