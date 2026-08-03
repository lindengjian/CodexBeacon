# First local milestone acceptance

This checklist is the release gate for the unsigned, owner-local Codex Beacon
build. It intentionally separates automated evidence from the macOS behaviors
that require a real Desktop session and physical display configuration.

## Reproducible unsigned build

Requirements: macOS 15 or newer, Apple Silicon, and Xcode 16 or newer.

```sh
swift test
./scripts/build-app.sh
file .build/CodexBeacon.app/Contents/MacOS/CodexBeacon
codesign -dvv .build/CodexBeacon.app 2>&1 || true
open .build/CodexBeacon.app
```

Expected results:

- `swift test` succeeds.
- `file` reports an `arm64` Mach-O executable.
- `codesign` reports an ad-hoc linker signature with no Team Identifier; this
  is expected for the owner-local, non-distributed first milestone.
- The bundle starts on macOS 15 or newer and creates neither a Dock icon nor a
  menu-bar item.

## Automated and protocol acceptance

Run `swift test`. The scenario suites exercise the application coordination
seam with controlled App Server messages, time, and macOS-environment events.
They cover the status priority, passive task observation, waiting and
completion confirmation, task/额度 isolation, dynamic 额度窗口 selection,
confirmable 额度重置, title privacy, accessibility motion reduction, display
placement, and hidden-Beacon behavior.

Protocol compatibility remains fail-closed: a missing shared runtime, an
unusable bundled CLI, a missing shared socket, a failed protocol handshake,
invalid protocol data, or stale monitoring evidence presents **监测不可用**
instead of **空闲**. Beacon does not gate this path on a CLI version allowlist.

## Real Codex Desktop and rollback acceptance

Use an installed Codex Desktop version and a non-sensitive test task.

1. Start the built Beacon and run the passive integration diagnostic.
2. If prompted, choose **修复集成**, save work, fully quit and reopen Codex
   Desktop, then rerun the diagnostic.
3. Confirm that a loaded `vscode` Desktop task appears in Beacon, task-status
   changes arrive, Beacon receives no server request requiring a response, and
   `codex://threads/<thread-id>` still opens the task.
4. Choose **恢复默认集成** (or quit Desktop and run
   `.build/CodexBeacon.app/Contents/MacOS/CodexBeacon --rollback-shared-daemon`),
   then fully quit and reopen Codex Desktop.
5. Confirm the labelled Beacon LaunchAgent is removed, the prior launchd
   environment value is restored, Desktop again uses its default private App
   Server topology, and the test task and sign-in state are unchanged.

The adapter does not classify CLI versions as supported or unsupported. It may
attempt any executable bundled by Codex Desktop, then remains in
**监测不可用** if the socket, protocol handshake, passive-observer behavior,
or shared Desktop runtime evidence cannot be verified.

Owner verification on 2026-07-28: passed. The supported shared-daemon Desktop
session observed loaded-task status without replying to server requests; the
rollback restored Desktop's default private App Server topology without
changing the verified task or sign-in state.

## macOS window matrix

Record the macOS version, display arrangement, notch presence, Dock setting,
and pass/fail result for every row on the owner machine.

| Scenario | Expected result |
| --- | --- |
| Normal windows and all Spaces | Beacon remains above normal windows and visible after switching through at least two Spaces. |
| Other-app full screen | Beacon remains visible above a native full-screen application. |
| Stage Manager and Mission Control | Beacon remains visible without activating itself or unexpectedly moving Spaces. |
| Single and multiple displays | Dragging snaps to the nearest edge; disconnect migrates it to the primary display and reconnect does not pull it back. |
| Menu bar, notch, permanent Dock | Beacon stays within the visible safe area and avoids each occupied region. |
| Auto-hidden Dock | Beacon can occupy the Dock edge without a permanent Dock-sized gap. |
| Notifications and approval panels | Quota notifications and Codex approval panels remain usable; Beacon neither receives nor answers Desktop's server requests. |
| Reduce Motion | No animation runs; waiting remains a green double ring and completed remains solid green. |

Owner verification on 2026-07-28: passed for every matrix row.

## System security boundary

Lock Screen, screen saver, and system security or authentication panels are
explicitly outside the product's coverage claim. Verify that Beacon does not
promise to remain visible over any of these macOS-protected surfaces.

Owner verification on 2026-07-28: passed. Beacon did not claim to cover or
interfere with the Lock Screen, screen saver, or system security/authentication
surfaces.

## Privacy review

Before delivery, verify all of the following:

- No telemetry, crash reporting, cloud synchronization, or automatic update
  check is present.
- Beacon communicates only with the local Codex App Server.
- Diagnostic export requires the user to open Settings and choose a destination
  folder; cancelling the panel writes no export.
- Exported diagnostics contain lifecycle and protocol metadata only, not raw
  App Server JSON, task titles/IDs, account fields, or local paths.
