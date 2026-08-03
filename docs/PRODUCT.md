# Codex Beacon Product Specification

## Purpose

Codex Beacon is an extremely small macOS companion for the Codex desktop app. It stays above other windows and makes Codex task state and the current account quota visible at a glance.

The first milestone is for the owner's own Apple Silicon Mac. It monitors only Codex desktop app tasks.

## Status Model

Codex Beacon aggregates all Codex desktop tasks into one dominant signal:

1. Monitoring unavailable
2. Waiting for you
3. Working
4. Completed
5. Idle

The higher state wins when tasks are in different states. Failed, interrupted, and cancelled tasks leave the aggregate and produce no special signal; if nothing else is active, the result is idle.

### Physical Lights

The body always contains three lights:

- Top red: task monitoring is unavailable.
- Middle amber: at least one task is working.
- Bottom green, flashing: at least one task is waiting for approval, authorization, or an answer.
- Bottom green, steady: at least one completion has not been confirmed.
- All lights off with dim recess outlines: idle.

Amber breathes slowly while working. Flashing green is faster and more explicit. Red unavailable and green completed remain steady.

When macOS Reduce Motion is enabled, all animation stops. Waiting becomes a green double ring, while completed remains solid green and working remains solid amber.

Quota availability is independent from task monitoring. A quota failure turns only the quota gauge into a gray dashed state; it does not light red or suppress a valid task signal.

## Completion And Attention

Clicking Codex Beacon opens or focuses the Codex desktop app and confirms all completions that existed at that moment.

A completion is automatically confirmed only when, at the instant of completion:

- Codex is the frontmost application; and
- the active Codex window is on the same display as Codex Beacon.

Moving Codex or Codex Beacon into that arrangement later does not silently confirm an existing completion.

Unconfirmed completions do not survive a Codex Beacon restart or a macOS restart. Real approval, authorization, or question requests are restored after restart if Codex still reports them as pending.

When multiple tasks are waiting for the user, the task that has waited longest is the primary click target. Beacon opens it through `codex://threads/<thread-id>`; the installed Codex Desktop release has passed this capability test. If the route is unavailable on an older release or the task no longer exists, Beacon focuses Codex and identifies the target in its detail UI, subject to the task-title privacy setting.

## Quota

Quota always belongs to the account currently signed in to the Codex desktop app. It never aggregates multiple accounts and does not represent a task context window.

The permanent gauge represents the shortest quota window currently reported for that account:

- If a short rolling window exists, it is shown.
- If the short window disappears, the next shortest reported window is shown.
- If only a weekly window exists, the weekly window is shown.
- A short window that later reappears automatically becomes current again.

No duration, including five hours, is hard-coded. Hover details list every reported window with remaining percentage and reset time.

Switching Codex accounts clears the old quota baseline and establishes a new one. The resulting percentage change is not treated as a quota reset.

## Reset Alerts

Every confirmable automatic or manual quota reset produces an alert; there is no low-quota threshold.

The alert combines:

- A macOS time-sensitive notification banner.
- The chosen macOS system sound.
- A five-second highlighted pulse around the Beacon frame.
- A temporary expanded message: `额度已重置 · 100%`.

The three task lights do not change for a quota reset. Resets occurring within ten seconds are grouped into one alert that lists all restored windows and plays one sound.

While Codex Beacon is online, every reset observable through the Codex App Server is reported. After sleep or an app restart, one catch-up alert is sent for a reset within the last 24 hours when the before-and-after quota state proves that a reset occurred. The app does not guess or attempt to reconstruct multiple indistinguishable resets that happened while it was offline. First launch has no historical baseline and sends no catch-up alert.

The App Server has no dedicated reset event or reset history. A reset performed through Beacon is definitive. A reset performed elsewhere is inferred only when snapshot changes prove it; the UI and diagnostics must not present an inferred reset as a server-authored event.

## Window Behavior

Codex Beacon uses the same observable always-on-top behavior as the Codex desktop pet:

- Floats above normal windows.
- Appears on every macOS Space.
- Remains visible above full-screen applications.
- Can be temporarily hidden without stopping monitoring or alerts.
- Does not appear in the Dock or add a menu bar item.

The default global hide/show shortcut is `Control + Option + Command + C`. The user can record a replacement shortcut in Settings. Relaunching the app also restores a hidden Beacon.

### Size And Appearance

The default size is approximately `62 × 229 pt` vertically and `229 × 62 pt` horizontally. This is 2.6 times the original compact concept. A compact `24 × 88 pt` option is available in Settings.

The body is a near-black translucent capsule with light blur and a thin border. Unlit lamps retain dim recess outlines. Lit lamps use pure red, amber, and green without permanent text.

The quota gauge is a neutral thin rail along the long edge of the body. Precise numbers appear only on hover.

### Snapping

- Left and right edges use the vertical orientation.
- Top and bottom edges rotate the Beacon horizontally.
- Dragging snaps to the nearest edge of the current display.
- The saved position consists of display, edge, and along-edge offset.
- Menu bars, notches, and a permanently visible Dock are avoided.
- An auto-hidden Dock does not reserve space.
- If a display disconnects, the Beacon moves to the corresponding edge of the primary display.
- Reconnecting that display does not move the Beacon back automatically.

### Repeatable Window Acceptance

Build the application with `./scripts/build-app.sh`, launch
`.build/CodexBeacon.app`, and perform this matrix on macOS 15 or newer. Record
the macOS version, display arrangement, Dock setting, and result for each row.

| Scenario | Steps | Expected result |
| --- | --- | --- |
| All Spaces | Put Beacon at each of the four edges, then switch through at least two Spaces. | Beacon remains visible and retains its selected edge. |
| Full-screen app | Put a different app into a native full-screen Space, then switch to it. | Beacon remains visible above the app. |
| Edge orientation | Drag Beacon near each edge and release. | Left/right are vertical; top/bottom are horizontal; the nearest edge wins. |
| Safe areas | Repeat the four-edge drag on a display with a menu bar, notch if present, and a permanently visible Dock. | Beacon stays in the visible safe area and does not overlap those areas. |
| Auto-hidden Dock | Set the Dock to automatically hide, drag Beacon to the Dock edge, and release. | Beacon can occupy that edge without a permanent Dock-sized gap. |
| Disconnect migration | Place Beacon on an external display, disconnect it, then reconnect it. | It moves to the corresponding primary-display edge when disconnected and remains there after reconnecting. |

The implementation uses AppKit's named `.floating` window level and public
`.canJoinAllSpaces` and `.canJoinAllApplications` collection behaviors. No
numeric window level is used.

## Hover Details And Privacy

Hover reveals:

- Aggregate state and task counts.
- All quota windows, remaining percentages, and reset times.
- Last update time and any task-monitoring or quota error.

Task titles are hidden by default. Settings can enable them. The default hover summary uses counts such as `工作 2 · 等待你 1`.

## Settings

Right-clicking the Beacon opens a compact menu with:

- Settings
- Temporarily Hide
- Quit

The Settings window includes:

- Launch at login.
- Standard or compact size.
- A recorder for the global hide/show shortcut.
- Show task titles.
- Task-monitoring integration status and diagnostics.
- Notification permission status.
- Separate sound enablement and system-sound selection for Waiting for You, Completed, and Quota Reset.

Waiting for You and Completed sounds are off by default. Quota Reset sound is on by default. All three sound settings remain independently configurable.

## First Launch

A one-time compact setup window:

1. Detects the Codex desktop app.
2. Verifies that a supported Codex Desktop task-state integration is available.
3. Requests macOS notification permission.
4. Offers the Launch at Login checkbox, enabled by default.

After setup, only the Beacon remains. Settings can rerun diagnostics or repair the integration.

## Integration And Privacy

Codex Beacon uses:

- The documented Codex App Server protocol for account quota and quota updates.
- The documented Codex App Server runtime-state protocol over a shared Unix socket. Desktop adoption currently requires a capability-validated private launch compatibility adapter and one Desktop restart; Beacon does not reject future bundled CLI versions by version string, and fails closed only when the resulting socket, protocol, passive-observer behavior, or shared Desktop runtime evidence cannot be verified.

Codex Hooks may provide supplemental lifecycle hints, but they are not the source of truth: Hook input cannot identify the Desktop surface, does not report request-user-input waiting, and does not distinguish completed, failed, and interrupted turns. Codex Beacon will not parse private transcripts or rollout logs to fill those gaps.

Codex Beacon communicates with the local Codex App Server and has no telemetry, crash reporting, cloud sync, or automatic update check. Diagnostic data stays local and is exported only by explicit user action.

## Platform And Distribution

- User-facing name: Codex Beacon.
- Repository: [`lindengjian/CodexBeacon`](https://github.com/lindengjian/CodexBeacon).
- Native SwiftUI and AppKit app.
- Minimum macOS: 15.
- Initial architecture: Apple Silicon only.
- First milestone: unsigned local build for the owner's Mac.
- Future public release: signed and notarized standalone DMG outside the Mac App Store.

## Out Of Scope For The First Release

- Windows and Linux.
- Codex CLI, IDE extension, and remote tasks.
- Multiple-account aggregation.
- Task history and task lists.
- Cancelling, retrying, or otherwise controlling Codex tasks.
- Per-task context-window usage.
- Telemetry, crash reporting, and automatic updates.

## Known Capability Boundary

OpenAI documents `codex://threads/<thread-id>`, and the installed Desktop release passed a live open-and-focus test.

By default, Codex Desktop runs its App Server over private parent-process stdio. A separately launched App Server can list persisted Desktop tasks but reports even an actively running Desktop task as `notLoaded`.

The current official App Server supports a shared Unix-socket daemon, and the installed Desktop bundle contains an undocumented `CODEX_APP_SERVER_USE_LOCAL_DAEMON=1` compatibility path. A reversible spike proved that Desktop and Beacon can connect to one server and share exact runtime state. Task monitoring is therefore implementable for the tested personal macOS build, with the Desktop opt-in, bundled CLI path, and version check explicitly treated as compatibility risks rather than public contracts.

Beacon observes without resuming tasks: it reads loaded threads, filters out ephemeral/system threads, listens for global status changes, and fetches the newest turn only after a terminal transition. This preserves Desktop ownership of approvals and user-input requests.
