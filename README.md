# Codex Beacon

Codex Beacon is a native macOS accessory application. The current vertical
slice shows a single, non-activating Beacon: a near-black capsule whose task
lamp can distinguish monitoring unavailable, working, and idle states from
controlled App Server protocol scenarios. It fails closed to red until current
monitoring evidence is available.

## Requirements

- macOS 15 or newer
- Apple Silicon
- Xcode 16 or newer

## Build and run

```sh
swift build --arch arm64
swift run CodexBeacon
```

The process uses the accessory activation policy and creates neither a Dock
icon nor a menu bar item.

## Shared App Server recovery

Beacon uses the tested, version-gated Desktop shared-daemon compatibility path
only when the shared socket is unavailable. It starts no independent observer
daemon. After Beacon reports that the adapter is prepared, fully quit and
reopen Codex Desktop; Beacon stays open and reconnects automatically when it
observes a loaded `vscode` Desktop thread. Local diagnostics are stored at:

```text
~/Library/Application Support/CodexBeacon/task-monitoring-diagnostic.txt
```

To remove Beacon's labelled LaunchAgent and restore the previous launchd
environment value, quit Codex Desktop and run:

```sh
.build/debug/CodexBeacon --rollback-shared-daemon
```

Then reopen Codex Desktop to restore its default private App Server topology.

To assemble a launchable application bundle:

```sh
./scripts/build-app.sh
open .build/CodexBeacon.app
```

## Test

```sh
swift test
```

The scenario tests launch the complete application core through its public
coordination seam. They inject task, time, and system-environment events and
observe only public Beacon view state and effect intentions.
