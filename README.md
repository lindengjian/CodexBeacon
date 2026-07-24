# Codex Beacon

Codex Beacon is a native macOS accessory application. The first vertical slice
shows a single, non-activating idle Beacon: a near-black capsule with three
recessed, unlit status lamps and a neutral quota track.

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
