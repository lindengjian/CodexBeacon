# Windows x64 public preview acceptance

This checklist is the release gate for the Windows 11 x64 Codex Beacon public preview. Automated tests can establish shared behavior, but cannot replace a real Windows device running the installed Codex Desktop app.

## Build and installation

On a clean or representative Windows 11 x64 user account:

1. Install the GitHub Release `Setup.exe` without administrator elevation.
2. Confirm the application is installed only for the current user under `%LocalAppData%\\Programs\\Codex Beacon`.
3. Confirm the Start menu entry launches the application and uninstall removes its own files, login-startup registration, and local Beacon integration state without modifying Codex tasks or sign-in state.
4. If the build is unsigned, confirm the release notes and README accurately explain the expected Windows SmartScreen warning; the installer must not attempt to bypass it.

## Core feature parity

With Codex Desktop installed and a non-sensitive test task available, verify that Windows Beacon:

- preserves the status priority **监测不可用 → 审批 → 工作 → 已完成 → 空闲**;
- treats a missing, stale, incompatible, or unverified local integration as **监测不可用**, never as **空闲**;
- passively observes Codex Desktop tasks and never resumes tasks, answers approvals or input requests, or reads private transcripts;
- displays dynamic account quota windows, uses the shortest available window as the current quota window, and preserves the existing confirmed-versus-inferred quota-reset boundary;
- opens or focuses the selected Codex task on click and applies the same completion-confirmation semantics;
- provides hover details, edge snapping, multi-display placement, hide/show, settings, login at startup, global shortcut, notification, and sound behavior with Windows-native equivalents; and
- preserves the default privacy posture: no telemetry, crash reporting, cloud sync, automatic update checks, or silent network access.

## Real-device integration and window matrix

Run the following on a real Windows 11 x64 device that has the supported Codex Desktop version installed. Record the Windows version, Codex Desktop version, display arrangement, task state, and pass/fail result.

| Scenario | Expected result |
| --- | --- |
| Initial integration | Diagnostics either establish a supported passive runtime connection or show **监测不可用** with actionable guidance; they never guess an idle state. |
| State transitions | Working, approval, completion, failure, interruption, and return to idle result in the documented aggregate behavior. |
| Codex focus and completion | Click opens or focuses the chosen task; only the documented explicit or same-display automatic condition confirms completion. |
| Single and multiple displays | The floating Beacon remains non-activating, snaps to the nearest edge of the active display, and follows the documented fallback when a display disconnects. |
| Normal and maximized windows | Beacon stays visible above normal application windows without preventing interaction with those windows. |
| Notifications, shortcut, and login startup | Notifications and task approval surfaces remain usable; the shortcut works after relaunch; the configured current-user startup entry launches only Beacon. |
| Security boundary | Beacon makes no claim to overlay the Windows lock screen, secure desktop, UAC prompt, or other protected system surfaces. |

The public preview may be released only after every applicable row passes. Any unverified local integration or platform behavior remains a release blocker, not a reason to weaken the fail-closed contract.
