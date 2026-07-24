# Codex Beacon Local Probe Results

Date: 2026-07-24
Host: macOS 26.5.2, Apple Silicon
Codex Desktop: `26.721.30844` (`com.openai.codex`)
Bundled Codex CLI/App Server: `0.144.4`

## Result summary

| Capability | Result | Decision |
| --- | --- | --- |
| Codex Hook as the task-state source | **Failed as sole source** | Keep Hooks only as a possible supplemental signal. They cannot identify Desktop origin, report `waitingOnUserInput`, or distinguish completed, failed, and interrupted turns. |
| Independent App Server quota access | **Passed** | Use the documented account methods for quota snapshots and dynamic windows. |
| Independent App Server observation of Desktop runtime state | **Failed** | Do not assume a separately launched server shares the Desktop server's loaded-thread state. |
| Existing-task deep link | **Passed** | Use `codex://threads/<thread-id>` as the primary click action. |
| Floating window level | **Passed for the baseline** | Use a floating `NSPanel` with the tested collection behaviors; retain a broader manual full-screen/Stage Manager matrix. |

## 1. Hook and Desktop runtime state

The generated protocol schemas from the installed `codex` binary contain the
desired runtime model:

- `ThreadStatus.active` with `waitingOnApproval` and
  `waitingOnUserInput`;
- `TurnStatus.inProgress`, `completed`, `interrupted`, and `failed`;
- `thread/status/changed`, `turn/completed`, approval requests, and
  request-user-input server requests.

However, those events belong to the App Server process that has the thread
loaded.

A separately launched `codex app-server --stdio` successfully listed persisted
Desktop tasks. The current Desktop task was classified as:

```json
{
  "source": "vscode",
  "status": { "type": "notLoaded" }
}
```

Filtering for `sourceKinds: ["appServer"]` returned no tasks. This proves two
important compatibility facts for the installed release:

1. Desktop tasks currently use the `vscode` source classification, not a
   dedicated `desktop` value.
2. An independent App Server does not mirror the Desktop process's live
   in-memory state.

Process inspection found that Codex Desktop launches:

```text
/Applications/ChatGPT.app/Contents/Resources/codex \
  -c features.code_mode_host=true \
  app-server --analytics-default-enabled
```

The process has private stdin/stdout/stderr socketpairs connected to its parent
Electron process. It exposes no listening TCP or filesystem Unix socket that a
companion can attach to. Attaching to those inherited file descriptors is not a
supported integration.

The installed Hook schema and official release documentation confirm that
Hooks provide `UserPromptSubmit`, `PermissionRequest`, and `Stop`, but:

- Hook input has no Desktop/client-surface field;
- `SessionStart.source` means `startup | resume | clear | compact`;
- there is no Hook event for request-user-input waiting;
- `Stop` has no final `completed | failed | interrupted` enum.

No global Hook was installed during this validation because executing one
would not repair these missing semantics and would mutate user configuration
without proving the required architecture.

### Conclusion

This probe established why the default topology fails: it uses private stdio
and an independent server cannot observe it. A later shared-daemon spike
resolved that boundary for the tested personal macOS build. With the installed
Desktop daemon opt-in enabled, Desktop and a passive client shared loaded
runtime state and exact status transitions.

The product may now enter a build specification with the private Desktop
launch opt-in explicitly version-gated and fail-closed. Private
transcript/JSONL parsing remains excluded because the official state protocol
is sufficient once both clients share the same server.

## 2. Quota protocol

An independent App Server initialized successfully and returned live data for:

- `account/rateLimits/read`;
- `account/usage/read`.

The response represented the currently authenticated ChatGPT plan and included
a dynamic quota bucket with:

- `usedPercent`;
- `windowDurationMins`;
- `resetsAt`;
- optional secondary windows;
- optional earned reset-credit data.

The observed account currently had only a weekly window, demonstrating why the
UI must not hard-code or require a five-hour window.

The generated schema and official documentation also contain
`account/rateLimits/updated`, but no update arrived during the short probe
because the account snapshot did not change.

There is no dedicated “reset happened” event or reset history. Beacon can:

- definitively report a reset it performs through
  `account/rateLimitResetCredit/consume`;
- infer a reset made elsewhere from a consumed-percentage drop plus an
  advanced reset boundary;
- infer at most a catch-up reset from persisted before/after snapshots while
  offline, without reconstructing multiple missed resets.

No reset credit was consumed during validation.

## 3. Existing-task deep link

The system URL handler for `codex://` resolved to:

```text
/Applications/ChatGPT.app
bundle id: com.openai.codex
```

Opening the current task with:

```text
codex://threads/<current-thread-id>
```

succeeded. A follow-up `NSWorkspace` check reported `com.openai.codex` as the
frontmost application. Installed first-party app code also constructs the same
route for “Open in app” and “copy deep link”.

### Conclusion

The primary click action can open the oldest waiting task directly. The
focus-plus-detail fallback remains useful for deleted tasks and older,
incompatible Desktop releases.

## 4. Window level

Runtime inspection of Codex Desktop showed:

- main Codex window: Core Graphics layer `0`;
- Codex pet composition/activity windows: layer `3`;
- Codex pet mascot effect: layer `2`.

A short-lived native `NSPanel` probe used:

```swift
panel.level = .floating
panel.isFloatingPanel = true
panel.hidesOnDeactivate = false
panel.collectionBehavior = [
    .canJoinAllSpaces,
    .canJoinAllApplications,
    .fullScreenAuxiliary,
    .stationary,
]
```

The probe reported:

```json
{
  "appKitLevel": 3,
  "cgWindowLayer": 3,
  "canJoinAllSpaces": true,
  "canJoinAllApplications": true,
  "fullScreenAuxiliary": true,
  "isFloatingPanel": true
}
```

This matches the Codex pet's primary floating layer on the tested system.
Apple's named constants must be used in production rather than hard-coding the
numeric value.

### Remaining manual matrix

The baseline still needs visual acceptance testing across:

- another app in full screen;
- multiple Spaces and multiple displays;
- Stage Manager and Mission Control;
- menu bar, Dock, notifications, approval panels, lock screen, and screen
  saver.

These tests refine behavior but do not block the basic native window
architecture.
