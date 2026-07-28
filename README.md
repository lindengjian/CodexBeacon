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

## First-time setup and diagnostics

On its first launch, Beacon opens a compact setup window. It detects Codex
Desktop and its bundled CLI, verifies the shared App Server version pair,
requests notification permission, and offers Launch at Login enabled by
default. The completion choice is saved, so later launches show only Beacon.

Settings can show the current notification authorization, change Launch at
Login, rerun the passive local diagnostic, prepare a supported shared-daemon
adapter, or restore the default Desktop topology. Preparing or restoring the
adapter never terminates Codex Desktop: save any work, fully quit and reopen
Codex Desktop, then rerun the diagnostic. Beacon never changes Codex tasks,
authentication, configuration, or private records.

## Shared App Server recovery

Beacon uses the tested, version-gated Desktop shared-daemon compatibility path
only when the shared socket is unavailable. It starts no independent observer
daemon. After Beacon reports that the adapter is prepared, fully quit and
reopen Codex Desktop; Beacon stays open and reconnects automatically when it
observes a loaded `vscode` Desktop thread. Local diagnostics are stored at:

```text
~/Library/Application Support/CodexBeacon/task-monitoring-diagnostic.txt
```

The file is reset when Beacon starts monitoring, then appends the current
run's connection lifecycle, protocol method/status metadata, task-state
resolution, and the state applied to the Beacon panel. It deliberately omits
raw App Server JSON, task IDs and titles, account fields, and local paths.
Writes are batched on a utility queue so diagnostics never delay task
monitoring. Choose **Export Diagnostic Log** in Settings to copy it into a
folder you select; each export gets a timestamped filename and preserves
earlier exports. No diagnostic data leaves the Mac unless you explicitly
export and share that copy.

To remove Beacon's labelled LaunchAgent and restore the previous launchd
environment value, quit Codex Desktop and run:

```sh
.build/CodexBeacon.app/Contents/MacOS/CodexBeacon --rollback-shared-daemon
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

## Local delivery acceptance

The local-milestone acceptance record, including the repeatable build steps,
automated checks, real Desktop integration procedure, and macOS window matrix,
is maintained in [docs/acceptance/first-local-milestone.md](docs/acceptance/first-local-milestone.md).
