import Foundation

/// The user-visible moments for which Beacon can play a system sound.
public enum BeaconSoundEvent: String, CaseIterable, Codable, Equatable, Sendable {
  case waiting
  case completion
  case quotaReset
}

/// One independently configurable event sound.
public struct BeaconSoundSetting: Codable, Equatable, Sendable {
  public var isEnabled: Bool
  public var soundName: String

  public init(isEnabled: Bool, soundName: String) {
    self.isEnabled = isEnabled
    self.soundName = soundName
  }
}

/// Persisted choices for Beacon's three event-sound categories.
public struct BeaconSoundPreferences: Codable, Equatable, Sendable {
  public var waiting: BeaconSoundSetting
  public var completion: BeaconSoundSetting
  public var quotaReset: BeaconSoundSetting

  public init(
    waiting: BeaconSoundSetting = .init(isEnabled: false, soundName: "Glass"),
    completion: BeaconSoundSetting = .init(isEnabled: false, soundName: "Hero"),
    quotaReset: BeaconSoundSetting = .init(isEnabled: true, soundName: "Ping")
  ) {
    self.waiting = waiting
    self.completion = completion
    self.quotaReset = quotaReset
  }

  public subscript(event: BeaconSoundEvent) -> BeaconSoundSetting {
    get {
      switch event {
      case .waiting: waiting
      case .completion: completion
      case .quotaReset: quotaReset
      }
    }
    set {
      switch event {
      case .waiting: waiting = newValue
      case .completion: completion = newValue
      case .quotaReset: quotaReset = newValue
      }
    }
  }
}

/// Reports only newly-present task events. Removing an event makes its next
/// appearance eligible to play a sound again, while repeated snapshots remain
/// silent.
public struct BeaconEventSoundTracker: Sendable {
  private var waitingTaskIDs: Set<String> = []
  private var completionTaskIDs: Set<String> = []

  public init() {}

  public mutating func observe(
    waitingTaskIDs newWaitingTaskIDs: Set<String>,
    unconfirmedCompletionTaskIDs newCompletionTaskIDs: Set<String>
  ) -> [BeaconSoundEvent] {
    defer {
      waitingTaskIDs = newWaitingTaskIDs
      completionTaskIDs = newCompletionTaskIDs
    }

    var events: [BeaconSoundEvent] = []
    if !newWaitingTaskIDs.subtracting(waitingTaskIDs).isEmpty {
      events.append(.waiting)
    }
    if !newCompletionTaskIDs.subtracting(completionTaskIDs).isEmpty {
      events.append(.completion)
    }
    return events
  }
}
