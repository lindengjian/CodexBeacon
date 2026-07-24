import AppKit
import CodexBeaconCore

let application = NSApplication.shared
let applicationDelegate = BeaconAppDelegate()

application.setActivationPolicy(.accessory)
application.delegate = applicationDelegate
application.run()
