import AppKit

/// Plays the named built-in macOS alert sound without requiring notification
/// permission. The names are the stable sounds shipped with macOS.
@MainActor
enum BeaconSystemSound {
  static let availableNames = [
    "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse",
    "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink",
  ]

  static func play(named name: String) {
    NSSound(named: NSSound.Name(name))?.play()
  }
}
