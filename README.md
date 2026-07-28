# Codex Beacon

[中文文档](README.zh-CN.md)

Codex Beacon is a native macOS companion for Codex Desktop. It presents the aggregate state of Codex Desktop tasks as a compact, non-activating traffic light and shows the current account quota in an edge gauge.

It fails closed: if it does not have current, reliable Desktop runtime evidence, it shows **monitoring unavailable** instead of mistaking that condition for idle.

## Status at a glance

| Idle | Working | Completed |
| :---: | :---: | :---: |
| ![Idle Beacon](docs/images/status-idle.png) | ![Working Beacon](docs/images/status-working.png) | ![Completed Beacon](docs/images/status-completed.png) |
| All task lamps are off. | The amber lamp breathes. | The green lamp stays lit until confirmed. |

| State | Signal | Meaning |
| --- | --- | --- |
| Monitoring unavailable | Steady red | Desktop monitoring evidence is missing, stale, or incompatible. |
| Waiting for you | Flashing green | A task needs approval, authorization, or an answer. |
| Working | Breathing amber | At least one task is active. |
| Completed | Steady green | At least one successful completion has not been confirmed. |
| Idle | All lamps off | No waiting, active, or unconfirmed-completion task remains. |

When tasks differ, the state order above determines the displayed signal. With macOS **Reduce Motion** enabled, animations stop; waiting is a double green ring so it remains distinct from a completed task.

## Features

- Monitors **Codex Desktop tasks only**, excluding CLI, IDE-extension, and remote tasks.
- Uses an always-visible floating panel that works across Spaces and eligible full-screen apps, snaps to screen edges, and creates neither a Dock icon nor a menu-bar item.
- Opens or focuses the relevant Codex task when clicked; that click also confirms completions that already existed.
- Shows hover details for aggregate task counts, quota windows, reset times, update time, and monitoring errors. Task titles are hidden by default and can be enabled in Settings.
- Automatically selects the shortest currently reported quota window—no fixed five-hour or weekly window is assumed.
- Alerts on a confirmable quota reset with a macOS notification, optional system sound, a five-second frame pulse, and a temporary message. Nearby resets are combined into one alert.
- Supports standard (`62 × 229 pt`) and compact (`24 × 88 pt`) sizes, a configurable global shortcut, launch at login, and separately configurable sounds for waiting, completion, and quota reset.

## Requirements

- macOS 15 or later
- Apple Silicon
- Xcode 16 or later
- Codex Desktop installed locally

This Swift Package has no third-party package dependencies.

## Build, run, and test

```sh
# Test
swift test

# Build and run with SwiftPM
swift build --arch arm64
swift run CodexBeacon

# Build an application bundle
./scripts/build-app.sh
open .build/CodexBeacon.app
```

The first launch opens setup to check the local Codex Desktop integration, request notification permission, and offer **Launch at Login** (on by default). Beacon then runs as an accessory application without a Dock or menu-bar presence.

## Desktop integration

Beacon passively observes the local Codex App Server. Accurate live state requires Codex Desktop and Beacon to share the same Unix-socket App Server daemon. Beacon connects as a second initialized client, reads loaded threads, state notifications, the newest terminal turn, and quota snapshots. It never resumes or changes a task, answers server approval/input requests, or parses private transcripts.

Codex Desktop's default private stdio App Server cannot be safely attached after Desktop starts. If Settings reports monitoring unavailable:

1. Open **Settings** from Beacon's right-click menu and run the diagnostic.
2. Choose **Repair integration** only when it is offered.
3. Save your work, fully quit Codex Desktop, and reopen it.
4. Run the diagnostic again. Beacon needs an observed loaded Desktop runtime thread before it leaves the red unavailable state.

Repair writes only Beacon's labelled user LaunchAgent and a compatibility setting for the next Desktop process. It never quits Desktop or interrupts a task. The path is strictly version-gated: an unsupported or mismatched bundled Codex CLI keeps monitoring unavailable rather than using an unsafe fallback.

To restore the default private-App-Server topology, select **Restore Default Desktop Integration** in Settings, fully quit Desktop, and reopen it. After building the application bundle, the same rollback is available from the command line:

```sh
.build/CodexBeacon.app/Contents/MacOS/CodexBeacon --rollback-shared-daemon
```

## Use

- **Click** to open/focus the oldest waiting task, otherwise a completed or working task, and confirm existing completions.
- **Hover** to see state counts, quota windows, reset times, last update, and availability errors.
- **Drag** to any edge. Left/right edges are vertical; top/bottom edges are horizontal. The saved placement safely migrates to the primary display if a display disconnects.
- **Right-click** for Settings, temporary hide/show, or quit.
- Press **Control + Option + Command + C** (the default) to show or hide Beacon; replace it in Settings if needed.

## Privacy and diagnostics

Beacon communicates only with the local Codex App Server. It includes no telemetry, crash reporting, cloud sync, or automatic-update check.

Its local diagnostic trace is stored at:

```text
~/Library/Application Support/CodexBeacon/task-monitoring-diagnostic.txt
```

The trace records connection lifecycle and protocol/status metadata, but not raw App Server JSON, task IDs or titles, account fields, or local paths. It leaves the Mac only if you explicitly export a timestamped copy from Settings.

## Project layout

```text
Sources/CodexBeaconCore/  State aggregation, quota parsing, placement, and rendering rules
Sources/CodexBeacon/      AppKit/SwiftUI UI, App Server connection, setup, settings, and diagnostics
Tests/                    Core scenarios and macOS integration-boundary tests
docs/                     Product specification, acceptance evidence, architecture decisions, and research
scripts/build-app.sh      Creates the application bundle
```

See [the acceptance record](docs/acceptance/first-local-milestone.md) for detailed compatibility checks and the manual macOS window matrix, and [docs/PRODUCT.md](docs/PRODUCT.md) for the product specification.

## Scope and limitations

The current scope supports Apple Silicon macOS only. It does not aggregate multiple accounts, monitor CLI/IDE/remote tasks, retain task history, control tasks, report per-task context usage, or claim visibility above macOS-protected surfaces such as the Lock Screen or security panels.
