# Codex Beacon Official Contract Research

Date: 2026-07-24

Scope: public OpenAI Codex documentation and first-party `openai/codex` protocol
schemas, plus public Apple AppKit documentation and the installed macOS SDK
headers. This note distinguishes what those sources promise from what still
requires an experiment against the installed Codex desktop app.

## Executive result

| Area | Contract result | Consequence |
| --- | --- | --- |
| Codex Hook lifecycle and desktop-source filtering | **Not sufficient** | Hooks can mark selected lifecycle moments, but their documented input does not identify the Codex desktop app and does not carry the complete task state model. A global Hook cannot be the sole source of truth for this MVP. |
| Codex App Server task state | **Protocol and Unix transport sufficient; Desktop opt-in locally proven but private** | The protocol has exact active, waiting, idle, completion, failure, and interruption states. A live spike proved the installed Desktop can share the local Unix-socket server with a passive client, but the Desktop launch opt-in is not a public contract. |
| Account quota | **Sufficient for display; partial for reset detection** | Dynamic quota windows can be displayed without assuming a five-hour limit. A reset initiated through the same client is explicit; a reset initiated elsewhere has no explicit reset event or history and must be inferred from changing snapshots. |
| Existing-task deep link | **Documented** | `codex://threads/<thread-id>` is now an official route for an existing local chat. Precise task navigation is no longer an undocumented capability. |
| Always-on-top AppKit window | **Sufficient baseline; exact pet parity unproven** | AppKit has public APIs for floating, all Spaces, and eligible cross-application full-screen presence. No public source identifies the Codex pet's exact level or promises that a third-party window stays above every system UI. |

The pre-spec integration blocker is resolved for the tested personal macOS
build. Remaining risk is compatibility rather than protocol sufficiency:
Beacon must version-gate the private Desktop daemon opt-in and fail closed when
the installed Desktop/CLI combination does not support it.

## 1. Codex Hooks

### Documented facts

The official [Hooks documentation](https://developers.openai.com/codex/hooks)
defines these lifecycle events:

- During a turn: `PreToolUse`, `PermissionRequest`, `PostToolUse`,
  `PreCompact`, `PostCompact`, `UserPromptSubmit`, `SubagentStop`, and `Stop`.
- At session or subagent start: `SessionStart` and `SubagentStart`.
- At main-thread session end: `SessionEnd`.

A command Hook receives `session_id`, `transcript_path`, `cwd`,
`hook_event_name`, and `model`. Turn-scoped events also carry `turn_id`.
`UserPromptSubmit` includes the prompt, `PermissionRequest` runs when Codex is
about to ask for a supported approval, and `Stop` runs when a turn stops.

`SessionStart` has a field named `source`, but the documented values are
`startup`, `resume`, `clear`, and `compact`. In other words, this field says how
the session began; it is not the product surface that originated the session.

The same documentation also states:

- `PermissionRequest` covers approval paths such as shell escalation and
  managed-network approval and exposes the associated tool.
- `Stop` exposes `turn_id`, `stop_hook_active`, and the latest assistant
  message, but no final turn-status enum.
- `SessionEnd` can occur on archive/delete, normal shutdown, or after a
  conversation has been idle and unopened for 30 minutes. It is not a
  per-turn completion event.
- A transcript path can be provided, but its format is explicitly not a stable
  Hook interface.

### Not documented

The public Hook contract does not provide:

- a client, host, bundle, app, or surface identifier;
- a `desktop` origin value;
- the App Server's `waitingOnUserInput` state;
- a final `completed | failed | interrupted` value on `Stop`;
- a guarantee that every task state transition in the Codex desktop app emits a
  Hook suitable for passive state aggregation.

It also does not document a supported matcher that filters Hooks to the Codex
desktop app while excluding CLI and IDE sessions.

### Product implication

The existing product statement that a Hook can record “source classification”
and monitor only desktop-app tasks is not supported by the public Hook schema.
A Hook can still be useful as an optional signal or installation experiment,
but it cannot be the authoritative state transport for Codex Beacon.

In particular, reading the transcript to repair these missing fields would
replace one documented integration with an explicitly unstable private format,
which contradicts the integration ADR.

## 2. Codex App Server

### 2.1 Task-state contract

The official [Codex App Server documentation](https://developers.openai.com/codex/app-server)
defines a bidirectional JSON-RPC interface with `thread/status/changed`,
`turn/started`, `turn/completed`, approval requests, and user-input requests.
The current first-party schemas make the state model precise:

- [`ThreadStatus`](https://github.com/openai/codex/blob/main/codex-rs/app-server-protocol/src/protocol/v2/thread.rs)
  is `notLoaded`, `idle`, `systemError`, or `active`.
- An active thread can contain `waitingOnApproval` and
  `waitingOnUserInput` flags.
- [`TurnStatus`](https://github.com/openai/codex/blob/main/codex-rs/app-server-protocol/src/protocol/v2/turn.rs)
  is `inProgress`, `completed`, `interrupted`, or `failed`.
- `turn/completed` includes the final `Turn`; a failed turn includes an error.
- Approval and request-user-input messages carry `threadId` and `turnId`;
  their current payloads are defined in the first-party
  [`item.rs` schema](https://github.com/openai/codex/blob/main/codex-rs/app-server-protocol/src/protocol/v2/item.rs).

This maps directly to the agreed product model:

| Beacon meaning | App Server evidence |
| --- | --- |
| Working | `ThreadStatus.active` without a waiting flag, or an in-progress turn |
| Waiting for you | `activeFlags` contains `waitingOnApproval` or `waitingOnUserInput` |
| Completed | `turn/completed` with `status: completed` |
| Failed/interrupted becomes idle | `turn/completed` with `failed` or `interrupted`, followed by the thread's runtime state |
| Monitoring unavailable | App Server connection/protocol failure, not a task status |

The protocol also supports `thread/read`, `thread/list`, and
`thread/loaded/list`, so a client can establish an initial snapshot before
processing updates.

### 2.2 Source classification

The App Server has a more useful source model than Hooks, but it still does not
document a desktop-specific value.

The current first-party
[`Thread` schema](https://github.com/openai/codex/blob/main/codex-rs/app-server-protocol/src/protocol/v2/thread_data.rs)
returns a `source` whose known values are `cli`, `vscode`, `exec`, `appServer`,
custom strings, subagent sources, and `unknown`. It also has a separate optional
analytics `threadSource` classification. The
[`thread/list` filter schema](https://github.com/openai/codex/blob/main/codex-rs/app-server-protocol/src/protocol/v2/thread.rs)
likewise has no `desktop` case.

The App Server documentation says that omitting `sourceKinds` defaults the list
to interactive `cli` and `vscode` sources. It does not state which value the
Codex desktop app uses, whether that value is stable, or whether a custom value
is reserved for it.

### 2.3 Missing desktop observer contract

The App Server documentation explains how a client launches or connects to an
App Server, including stdio, WebSocket, and Unix-socket transports. The Unix
socket is a suitable local multi-client transport. It still does not promise
that:

- the released Codex desktop app exposes its running App Server socket to an
  unrelated local companion;
- that socket accepts a second passive client;
- a separately launched `codex app-server` mirrors loaded-thread runtime state
  from the desktop app's App Server process;
- an observer receives current state for desktop-owned threads without
  resuming or otherwise mutating them;
- source values can reliably exclude CLI/IDE work while retaining every desktop
  task.

This distinction matters because persisted thread history and live runtime
status are different things. A new App Server can read stored threads, but that
alone does not prove that it sees another process's live approvals and active
turn transitions.

### Product implication

App Server should become the intended task-state source, but only after a live
spike proves one of these supported architectures:

1. Codex Desktop uses the shared Unix-socket daemon and accepts an additional
   initialized subscriber; or
2. OpenAI documents another passive Desktop-state transport.

Launching an independent server and assuming its runtime state equals the
desktop app's state is not a valid implementation assumption.

The spike must record actual `Thread.source` values from desktop, CLI, and IDE
sessions. A value observed in one release is evidence for a compatibility
adapter, not a public guarantee; unknown values must fail closed rather than
silently mix non-desktop work into the aggregate.

## 3. Account quota and resets

### Documented facts

The App Server's
[`account/rateLimits/read`](https://developers.openai.com/codex/app-server#6-rate-limits-chatgpt)
response provides:

- a backward-compatible `rateLimits` view;
- optional `rateLimitsByLimitId`, keyed by metered bucket identifier;
- optional `primary` and `secondary` windows;
- `usedPercent`, `windowDurationMins`, and `resetsAt`;
- optional limit labels, plan metadata, reached-limit classification, credits,
  and reset-credit information.

This supports the product's dynamic-window rule. No five-hour duration needs to
be hard-coded: choose the shortest currently reported non-null window and
recompute when buckets appear or disappear.

`account/rateLimits/updated` is emitted when ChatGPT rate limits change. The
first-party
[`AccountRateLimitsUpdatedNotification`](https://github.com/openai/codex/blob/main/codex-rs/app-server-protocol/src/protocol/v2/account.rs)
is explicitly a **sparse** update; clients are told to merge it into the last
read result or refetch.

The documented
[`account/rateLimitResetCredit/consume`](https://developers.openai.com/codex/app-server#8-earned-rate-limit-resets-chatgpt)
operation returns one of:

- `reset`;
- `alreadyRedeemed`;
- `nothingToReset`;
- `noCredit`.

After `reset` or `alreadyRedeemed`, the client must refetch rate limits rather
than infer the new window from the consume response.

`account/read` exposes the active authentication/account kind. For a ChatGPT
account the public schema includes nullable email and plan type.
`account/updated` announces auth mode and plan type changes.

### Not documented

There is no public App Server method or notification for:

- “a reset happened” with reset cause, affected windows, or reset timestamp;
- a reset-event history;
- all manual resets performed by other clients;
- reconstructing multiple resets that happened while Beacon was offline.

`account/rateLimits/updated` means that a limit snapshot changed; its payload
does not identify a reset. A reset initiated through Beacon is definitive
because the consume result is explicit. A reset initiated in another client can
only be inferred from before-and-after window values.

The public account response also lacks a guaranteed stable ChatGPT account ID.
Email can be null, and `account/updated` contains auth mode and plan type rather
than account identity. Therefore, resetting the baseline on every observable
auth-mode change is supported, but distinguishing two same-plan accounts with
no email is not fully contracted.

The documentation does not guarantee that an independently launched App Server
will receive rate-limit updates caused by activity in the desktop app, nor does
it promise that its current account always tracks a desktop-account switch.

### Product implication

Quota display is ready for implementation once account sharing with the desktop
process is proved. The parser must:

- preserve all buckets by `limitId`;
- tolerate missing primary/secondary windows and missing duration/reset fields;
- merge sparse updates or immediately refetch;
- compute remaining percentage as `100 - usedPercent`;
- never assume a five-hour window exists.

The reset-alert promise needs narrower language:

- **Definitive:** a reset performed through this App Server connection returns
  `reset` or idempotent `alreadyRedeemed`.
- **Inferred:** an observed bucket's consumed percentage drops and its reset
  boundary advances in a way consistent with a reset.
- **Offline:** at most one catch-up event can be inferred from persisted
  before/after state; multiple resets cannot be reconstructed.

“Every reset observable online” is reasonable only after proving that the
desktop and Beacon share the same live rate-limit update stream. The protocol
by itself does not prove it.

## 4. Existing-task deep links

### Documented facts

The official [Codex command reference](https://developers.openai.com/codex/reference/commands#deep-links)
now lists:

```text
codex://threads/<thread-id>
```

It says this opens an existing local chat and that `<thread-id>` is the chat's
technical thread ID. The same page says the ChatGPT desktop app retains the
`codex://` scheme for compatibility.

The App Server's `threadId` is therefore the correct value to place in this
route.

### Not documented

The reference does not promise:

- success for a deleted, unavailable, or non-local thread;
- which existing Codex window/display receives the navigation;
- that opening the URL never creates or reuses a window;
- behavior on older desktop releases that predate this route.

### Product implication

Codex Beacon can use the deep link as its primary click action:

```swift
NSWorkspace.shared.open(URL(string: "codex://threads/\(threadID)")!)
```

The product's focus-plus-detail fallback should remain for invalid/unavailable
threads and version compatibility, but the route itself should no longer be
described as undocumented. “Oldest waiter first” can be implemented by storing
the time at which each App Server thread first enters a waiting flag, then
opening that thread ID.

## 5. AppKit always-on-top and full-screen behavior

### Documented facts

Apple provides separate contracts for window level, Spaces membership, and
full-screen participation:

| API | Apple contract | Beacon use |
| --- | --- | --- |
| [`NSWindow.Level`](https://developer.apple.com/documentation/appkit/nswindow/level-swift.struct) | Higher window levels are ordered above lower levels. `.floating` is the standard floating-window level. | Initial level should be `.floating`. |
| [`NSPanel`](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/WinPanel/Concepts/UsingPanels.html) | A floating panel can remain above standard windows; panels normally hide when their app deactivates. | Use an `NSPanel` and set `hidesOnDeactivate = false`. |
| [`.canJoinAllSpaces`](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallspaces) | The window can appear in all Spaces. | Required. |
| [`.canJoinAllApplications`](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallapplications) | On macOS 13+, an eligible window can join other applications' sets and full-screen Spaces; Apple identifies floating windows and system overlays as common uses. | Required baseline for the macOS 15 minimum. |
| [`.fullScreenAuxiliary`](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/fullscreenauxiliary) | The window can appear alongside a full-screen window. | Include in the experiment matrix; Apple does not say it alone crosses application ownership. |
| [`orderFrontRegardless()`](https://developer.apple.com/documentation/appkit/nswindow/orderfrontregardless()) | Orders the window to the front of its current level even when the application is inactive; Apple says to use it sparingly. | Suitable for initial display/recovery, not a polling loop. |

The installed macOS 26.5 SDK's first-party `NSWindow.h` adds two relevant
constraints:

- `.canJoinAllApplications` is available from macOS 13 and is described as
  appropriate for floating windows and system overlays.
- Apple requires at most one of the collection behaviors `.primary`,
  `.auxiliary`, and `.canJoinAllApplications`.

The initial public-API baseline is therefore:

```swift
panel.isFloatingPanel = true
panel.hidesOnDeactivate = false
panel.level = .floating
panel.collectionBehavior = [
    .canJoinAllSpaces,
    .canJoinAllApplications,
    .ignoresCycle
]
```

`.fullScreenAuxiliary` should be tested both on and off rather than assumed
necessary.

### Not documented

Apple does not promise:

- an “always above everything” level for third-party apps;
- that `.floating` sits above menus, popovers, modal security panels, screen
  savers, the lock screen, or every other elevated window;
- eligibility details for every style-mask/level combination under
  `.canJoinAllApplications`;
- the exact level or collection behavior used by the Codex desktop pet;
- identical behavior across Mission Control, Stage Manager, full-screen video,
  and multi-display configurations.

`.statusBar` exists, but Apple describes it as the status-window level, not as
the recommended level for an arbitrary desktop overlay. It is a candidate for
comparison, not the default contract.

### Product implication and test matrix

The public APIs are strong enough to implement the MVP, but “same as the Codex
pet” remains an observable acceptance criterion rather than a documented
configuration.

The window spike should compare `.floating` and `.statusBar`, and compare the
baseline collection behaviors with and without `.fullScreenAuxiliary`, across:

- Codex, Safari, and a video player in full screen;
- ordinary Spaces and switching between them;
- Stage Manager on and off;
- Mission Control;
- one and multiple displays;
- menu bar, Dock, notification, approval-panel, lock-screen, and screen-saver
  interactions.

The app must use named `NSWindow.Level` constants rather than hard-coded
CoreGraphics numeric levels because Apple reserves the right to change level
values.

## 6. Required specification corrections

Before `/to-spec`, update the product and integration ADR to reflect:

1. The existing-thread deep link is documented and can be the primary path.
2. Hook `SessionStart.source` is not desktop-source classification.
3. Hooks are not the authoritative task-state source.
4. App Server task events are the intended source, conditional on a successful
   live desktop-observer attachment test.
5. Quota reset notifications outside Beacon's own consume request are inferred,
   not explicit protocol events.
6. Exact Codex-pet window parity remains a runtime acceptance test.

If passive desktop App Server attachment fails, the task-monitoring design is
not ready for `/to-spec`; the next step is an OpenAI-supported integration
request or a deliberate product-scope change, not parsing private logs.
