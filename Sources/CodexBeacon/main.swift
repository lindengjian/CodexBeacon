import AppKit
import CodexBeaconCore

if CommandLine.arguments.contains("--rollback-shared-daemon") {
  DesktopDaemonCompatibilityAdapter().rollback()
  exit(EXIT_SUCCESS)
}

let application = NSApplication.shared
let applicationDelegate = BeaconAppDelegate()

application.setActivationPolicy(.accessory)
application.delegate = applicationDelegate
application.run()
