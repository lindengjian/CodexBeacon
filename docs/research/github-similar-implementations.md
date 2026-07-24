# GitHub Similar-Implementation Research

Date: 2026-07-24

Scope: public GitHub repositories that monitor Codex task activity or account
quota. The review used repository source, README files, tests, and linked
issues/PRs rather than third-party articles. Every source link below is pinned
to the commit inspected unless the link intentionally points to an issue or
pull request.

## Executive result

The ecosystem has converged on two different integration families:

1. Quota tools launch a separate `codex app-server` and call
   `account/rateLimits/read`, or parse `rate_limits` from local rollout JSONL.
   The App Server path is the cleaner choice for Codex Beacon.
2. Tools that display accurate Codex task states combine official Hooks with
   private `~/.codex/sessions/**/rollout-*.jsonl` parsing. Hooks cover prompt,
   tools, approval, and stop; JSONL supplies Desktop attribution,
   `request_user_input`, completed-versus-aborted semantics, and fallback when a
   `Stop` Hook is missed.

No inspected third-party status tool obtains passive, per-thread Codex Desktop
runtime state by attaching a second client to the Desktop-owned App Server. No
inspected project uses Codex's private Electron IPC or
`process_manager/chat_processes.json` for the state machine. One project reads
`state_*.sqlite`, but only for thread title and agent-path metadata—not live
task status.

There is, however, a newly relevant first-party path that deserves a separate
probe: `openai/codex` now has an experimental managed App Server daemon, Unix
control socket, and `app-server proxy`. Inspection of the installed Codex
Desktop bundle found a `CODEX_APP_SERVER_USE_LOCAL_DAEMON` opt-in for that
socket. None of the status-light repositories below use this route, and the
Desktop opt-in is not yet a documented companion-app contract, but it may
remove the earlier “private parent stdio only” limitation if it works in the
installed Desktop release.

| Project | Working | Waiting | Completed / idle | Desktop-only filter | Quota / reset |
| --- | --- | --- | --- | --- | --- |
| `clawd-on-desk` | Hook + JSONL | Official `PermissionRequest`; JSONL `request_user_input` | Hook `Stop` plus JSONL `task_complete` / `turn_aborted` | Yes, by private rollout `session_meta.originator` allowlist | JSONL `token_count.payload.rate_limits`; no App Server |
| `CodexBar` | Recent transcript mtime only | Not implemented | `active` / `idle` age heuristic only | Yes, by rollout originator/source plus `codex app-server` process presence | App Server and OAuth; robust inferred reset detection |
| `agent-status-light` | Rollout user/end timestamps | Rollout call/output correlation plus approval heuristics | `task_complete`/`final_answer` versus abort/end | No | None |
| `codex-traffic-light-mxp-desktop` | Hook; private SQLite log fallback | Hook only | Hook `Stop`; SQLite silence heuristic | No reliable filter | App Server, but fixed 300/10080-minute lanes |
| `codex-usage-menubar` | Rollout `task_started` | Not implemented | Rollout `task_complete`/`turn_aborted` | No | Short-lived App Server |
| `tmux-agent-status` | Hook events | Manual tmux wait state, not Codex approval | Hook `Stop` → `done` | No; tmux/CLI scope | None |
| `codex-limit` | None | None | None | Not applicable | Short-lived App Server RPC |
| `codex-gnome-extension` | None | None | None | No | JSONL `rate_limits`, with hard-coded 5-hour/week durations |

## 1. `rullerzhou-afk/clawd-on-desk`

Inspected version: package `0.13.0`, commit
[`c1ba963144fde5dbf94082991c2848d827b363d9`](https://github.com/rullerzhou-afk/clawd-on-desk/tree/c1ba963144fde5dbf94082991c2848d827b363d9).

This is the closest known implementation to Codex Beacon's desired task-state
behavior. Its README describes Codex as
["official hooks with JSONL fallback"](https://github.com/rullerzhou-afk/clawd-on-desk/blob/c1ba963144fde5dbf94082991c2848d827b363d9/README.md#L40),
and the implementation confirms that this is a genuine hybrid rather than a
Hook-only monitor.

### State derivation

The public Hook handler maps:

- `SessionStart` → idle;
- `UserPromptSubmit` → thinking;
- `PreToolUse` and `PostToolUse` → working;
- `Stop` → a provisional idle/turn-end signal;
- `PermissionRequest` → a separate blocking approval path.

See
[`hooks/codex-hook.js`](https://github.com/rullerzhou-afk/clawd-on-desk/blob/c1ba963144fde5dbf94082991c2848d827b363d9/hooks/codex-hook.js#L37-L45)
and the constructed state payload in
[`buildStateBody`](https://github.com/rullerzhou-afk/clawd-on-desk/blob/c1ba963144fde5dbf94082991c2848d827b363d9/hooks/codex-hook.js#L328-L393).
The Hook payload is correlated to the rollout through `transcript_path`, after
which the handler reads the rollout's first `session_meta` record to add source,
originator, and subagent role.

The fallback monitor polls `~/.codex/sessions` every 1.5 seconds. Its mapping
includes:

- `task_started` and `user_message` → thinking;
- function/tool calls and `guardian_assessment` → working;
- `task_complete` → turn end;
- `turn_aborted` → idle.

The complete table is in
[`agents/codex.js`](https://github.com/rullerzhou-afk/clawd-on-desk/blob/c1ba963144fde5dbf94082991c2848d827b363d9/agents/codex.js#L19-L50).
At turn end it emits completion attention only when the root turn used a tool
or produced assistant output; subagents and metadata-only completions become
idle. An aborted turn clears pending questions and becomes idle. See the
[`task_complete` / `turn_aborted` logic](https://github.com/rullerzhou-afk/clawd-on-desk/blob/c1ba963144fde5dbf94082991c2848d827b363d9/agents/codex-log-monitor.js#L914-L959).

This fallback is not theoretical. PR
[#422](https://github.com/rullerzhou-afk/clawd-on-desk/pull/422) added JSONL
`task_complete` rescue because some local Codex turns did not receive an
official `Stop`.

### Waiting states

Approval waiting now comes exclusively from the official
`PermissionRequest` Hook. PR
[#571](https://github.com/rullerzhou-afk/clawd-on-desk/pull/571) removed an older
two-second JSONL approval heuristic because slow commands and Codex Desktop's
write cadence caused false positives. This is strong evidence that inferring
approval from a quiet function call is not production-safe.

Codex questions are different: because there is no corresponding Hook,
`clawd-on-desk` parses private rollout records. A
`response_item/function_call` named `request_user_input` opens the waiting
state; the matching `function_call_output` resolves it. See
[`hooks/codex-user-input.js`](https://github.com/rullerzhou-afk/clawd-on-desk/blob/c1ba963144fde5dbf94082991c2848d827b363d9/hooks/codex-user-input.js#L77-L90)
and the monitor's
[`pendingUserInputs` correlation](https://github.com/rullerzhou-afk/clawd-on-desk/blob/c1ba963144fde5dbf94082991c2848d827b363d9/agents/codex-log-monitor.js#L1133-L1200).
The monitor has bounded startup recovery, stale-question age caps, backfill
suppression, and per-call correlation, illustrating the operational complexity
introduced by tailing transcripts.

### Desktop-only attribution

The Hook contract itself is not used to identify Desktop. The project reads
`session_meta.originator` from the rollout and recognizes only:

- `codex desktop`;
- `codex_work_desktop`.

The allowlist and its compatibility comment are in
[`hooks/codex-originator.js`](https://github.com/rullerzhou-afk/clawd-on-desk/blob/c1ba963144fde5dbf94082991c2848d827b363d9/hooks/codex-originator.js#L3-L18).
The comment records that the observed originator changed between Codex `0.142.0`
and `0.144.2`. This means Desktop-only filtering is feasible with today's
rollouts, but the identifier is private and already has demonstrated version
churn.

### Quota

The project reads subscription quota from
`event_msg/token_count.payload.rate_limits`, not from App Server. It treats
reported `window_minutes` as authoritative, including the case where only a
weekly primary window exists, and rejects stale/future-dated captures. See
[`hooks/codex-rate-limits.js`](https://github.com/rullerzhou-afk/clawd-on-desk/blob/c1ba963144fde5dbf94082991c2848d827b363d9/hooks/codex-rate-limits.js#L5-L95)
and the
[`token_count` handling](https://github.com/rullerzhou-afk/clawd-on-desk/blob/c1ba963144fde5dbf94082991c2848d827b363d9/agents/codex-log-monitor.js#L863-L891).

This source can lag until some Codex task emits a fresh `token_count`; it is
therefore inferior to an independent App Server read for Codex Beacon's
always-visible account quota.

### Maintenance assessment

This approach can implement all four Codex Beacon task states and filter to
Desktop, but it depends on private record names, fields, timing, and rollout
layout. Its extensive recovery and deduplication code is evidence of real
maintenance cost, not optional polish. Adopting it would contradict
ADR-0002's current ban on transcript/rollout parsing.

## 2. `steipete/CodexBar`

Inspected version: commit
[`cc8da27cec92029a6435bfee4a703a719290234e`](https://github.com/steipete/CodexBar/tree/cc8da27cec92029a6435bfee4a703a719290234e).

CodexBar is the strongest reference for quota and reset handling, but not for
precise task state.

### Account quota

The CLI path starts:

```text
codex -s read-only -a untrusted app-server
```

It initializes newline-delimited JSON-RPC, then serially calls
`account/rateLimits/read` and `account/read`, with bounded startup/request
timeouts and child-process shutdown. See
[`CodexRPCClient`](https://github.com/steipete/CodexBar/blob/cc8da27cec92029a6435bfee4a703a719290234e/Sources/CodexBarCore/UsageFetcher.swift#L1000-L1136)
and
[`loadLatestCLIAccountSnapshot`](https://github.com/steipete/CodexBar/blob/cc8da27cec92029a6435bfee4a703a719290234e/Sources/CodexBarCore/UsageFetcher.swift#L1298-L1357).
It reads dynamic `windowDurationMins`, `usedPercent`, and `resetsAt`, plus
account identity and credits.

CodexBar also has an OAuth-first path that reads `~/.codex/auth.json` and calls
ChatGPT backend endpoints. Those endpoints are useful implementation evidence
but are not a public companion-app contract, so Codex Beacon should retain the
documented App Server path.

### Reset detection

CodexBar infers a reset from successive quota snapshots rather than receiving a
reset event. Its detector:

- keys state by provider and account;
- requires a previous usage above 1% followed by usage at or below 1%;
- requires the reset boundary to advance;
- for Codex weekly resets, requires a prior boundary;
- persists the detector baseline;
- emits a `quota_reset` Hook and local notification event after confirmation.

See
[`UsageStore+LimitResetCelebration.swift`](https://github.com/steipete/CodexBar/blob/cc8da27cec92029a6435bfee4a703a719290234e/Sources/CodexBar/UsageStore%2BLimitResetCelebration.swift#L80-L237).
Codex has additional weekly confirmation logic that validates monotonic
timestamps and equivalent reset boundaries before publishing an apparent
near-zero reset; see
[`CodexWeeklyResetConfirmation.swift`](https://github.com/steipete/CodexBar/blob/cc8da27cec92029a6435bfee4a703a719290234e/Sources/CodexBar/Providers/Codex/CodexWeeklyResetConfirmation.swift#L19-L152).

This is directly reusable as a design reference for Codex Beacon's “any reset”
alert, including manual resets: a manual reset is observable when the next
fresh snapshot crosses down and advances the boundary. As with any polling
scheme, multiple resets while the tool is offline cannot be reconstructed.

### Task/session activity

CodexBar intentionally does not implement working/waiting/completed. Its local
scanner combines:

- `ps` process enumeration;
- `lsof` cwd lookup;
- rollout filename/mtime;
- only the first `session_meta` line;
- an `active` heuristic when the transcript changed within 120 seconds,
  otherwise `idle`.

The design explicitly lists “waiting on permission” as a non-goal; see
[`docs/agent-sessions-design.md`](https://github.com/steipete/CodexBar/blob/cc8da27cec92029a6435bfee4a703a719290234e/docs/agent-sessions-design.md#L31-L46)
and its
[`Non-goals`](https://github.com/steipete/CodexBar/blob/cc8da27cec92029a6435bfee4a703a719290234e/docs/agent-sessions-design.md#L92-L98).
The process scanner excludes `codex app-server` as a task process; it uses the
presence of App Server only as a weak indication that the Desktop app exists.
See
[`AgentSession.swift`](https://github.com/steipete/CodexBar/blob/cc8da27cec92029a6435bfee4a703a719290234e/Sources/CodexBarCore/AgentSession.swift#L216-L265).

Desktop attribution comes from private rollout `originator`/`source` strings
containing `desktop` or `app-server`; see
[`CodexRolloutMetadata.sessionSource`](https://github.com/steipete/CodexBar/blob/cc8da27cec92029a6435bfee4a703a719290234e/Sources/CodexBarCore/AgentSession.swift#L497-L535).
This is broader but less conservative than `clawd-on-desk`'s exact allowlist.

### SQLite and process inspection

CodexBar does read the newest `state_*.sqlite`, but only:

```sql
SELECT title, agent_path FROM threads WHERE id = ?1 LIMIT 1
```

The database is opened read-only and serves as a best-effort title fallback;
it is not used to infer live state. See
[`CodexThreadMetadataReader.swift`](https://github.com/steipete/CodexBar/blob/cc8da27cec92029a6435bfee4a703a719290234e/Sources/CodexBarCore/CodexThreadMetadataReader.swift#L28-L98).
No private Codex Electron IPC or `process_manager` file is used.

### Maintenance assessment

The quota implementation is a high-value reference. Its task activity model is
deliberately approximate and cannot drive Codex Beacon's green flashing versus
steady states. Its read-only SQLite title lookup also demonstrates that
`state_*.sqlite` is usable for display metadata, but provides no evidence that
database rows are a reliable passive runtime-state transport.

## 3. `kajiwara321/codex-limit`

Inspected version: package `1.0.0`, commit
[`3ced8282776a6a1c8795303f42d11d9f37371733`](https://github.com/kajiwara321/codex-limit/tree/3ced8282776a6a1c8795303f42d11d9f37371733).

This is the minimal proof of the quota architecture. It spawns a short-lived
`codex app-server`, sends `initialize` followed by
`account/rateLimits/read`, returns `result.rateLimits`, and kills the process.
See
[`index.js`](https://github.com/kajiwara321/codex-limit/blob/3ced8282776a6a1c8795303f42d11d9f37371733/index.js#L36-L108).

It has no background state monitoring, Desktop filtering, reset detection, or
notifications. Its README calls App Server experimental and warns that Codex
updates may break it. The code also documents primary as “typically” five
hours, so consumers still need to use `windowDurationMins` rather than assume a
fixed primary duration.

Maintenance risk is low compared with transcript parsing: the integration is a
small JSON-RPC client, and failures are bounded by a 15-second timeout. It
validates Codex Beacon's choice to keep account quota independent from the
Desktop-owned task runtime.

## 4. `almighty-shogun/codex-gnome-extension`

Inspected version: commit
[`1e00342d967aec8c3c48af8de46c31a3ec36a634`](https://github.com/almighty-shogun/codex-gnome-extension/tree/1e00342d967aec8c3c48af8de46c31a3ec36a634).

This GNOME status-strip implementation scans the 20 newest files under
`~/.codex/sessions` every 30 seconds, caching parse results by path and mtime.
It reads every changed JSONL file backwards and extracts
`event_msg/token_count.payload.rate_limits`; see
[`extension.js`](https://github.com/almighty-shogun/codex-gnome-extension/blob/1e00342d967aec8c3c48af8de46c31a3ec36a634/extension.js#L332-L405)
and
[`_extractSnapshotsFromFile`](https://github.com/almighty-shogun/codex-gnome-extension/blob/1e00342d967aec8c3c48af8de46c31a3ec36a634/extension.js#L448-L503).

It has no task-state detection or Desktop attribution. More importantly, it
hard-codes `300` minutes as five-hour and `10080` as weekly in
[`_getLimitsByWindow`](https://github.com/almighty-shogun/codex-gnome-extension/blob/1e00342d967aec8c3c48af8de46c31a3ec36a634/extension.js#L505-L524).
That would fail Codex Beacon's requirement when the five-hour window disappears
or a new duration is introduced.

It displays reset timestamps and expires stale cached windows after their
reported boundary/window age, but does not notify on reset. Its value is mainly
as a compact Linux UI reference and as evidence that JSONL quota can work
without network access—not as a suitable protocol model.

## 5. `samleeney/tmux-agent-status`

Inspected version: commit
[`037af053aeb15219fd6b7dd2d6a0d76c83f46001`](https://github.com/samleeney/tmux-agent-status/tree/037af053aeb15219fd6b7dd2d6a0d76c83f46001).

This project is a concise Hook-only counterexample. Its Codex handler ignores
the JSON payload and uses only the event name:

- `SessionStart` → `done`;
- `UserPromptSubmit` and tool Hooks → `working`;
- `Stop` → `done`.

See
[`hooks/codex-hook.sh`](https://github.com/samleeney/tmux-agent-status/blob/037af053aeb15219fd6b7dd2d6a0d76c83f46001/hooks/codex-hook.sh#L112-L142).

The visible `wait` status is a user-managed tmux override, not
`PermissionRequest` or `request_user_input`. The integration is inherently
CLI/tmux-scoped and does not filter Codex Desktop. It also treats every `Stop`
as successful completion, so it cannot meet Codex Beacon's requirement that
failed, interrupted, or cancelled turns become idle.

This implementation is easy to maintain precisely because it accepts a
coarser state model. It confirms that Hooks alone are enough for a simple
working/done indicator, but not for Codex Beacon's product semantics.

## Cross-project findings

### How each candidate signal performs

| Signal | What repositories demonstrate | Suitability for Codex Beacon |
| --- | --- | --- |
| Official Hooks | Fast working/completion edges and authoritative approval requests | Necessary supplemental signal, but insufficient alone |
| Rollout JSONL | Desktop origin, precise `request_user_input`, task completion/abort, quota snapshots | Functionally sufficient, privately versioned, high maintenance |
| Independent App Server | Reliable account/quota reads | Preferred for account quota; a separate stdio process does not expose Desktop-owned live thread state |
| Shared Unix-socket App Server | No inspected community implementation | Official transport exists; installed Desktop opt-in needs a controlled local spike |
| `state_*.sqlite` | Thread title/agent-path enrichment | Metadata only in inspected code; no proof for runtime state |
| Process detection | Agent/App presence and rough activity correlation | Cannot distinguish waiting/completed and is unsuitable as source of truth |
| File mtime | Cheap active/idle approximation | Too noisy for traffic-light semantics |
| Codex private Electron IPC | No inspected implementation | No community evidence of a stable approach |
| `process_manager` files | No inspected implementation | No community evidence of a stable approach |

### Reset alerts

The best observed reset design is CodexBar's snapshot transition detector:

1. persist a per-account, per-window baseline;
2. require a meaningful prior used percentage;
3. observe a drop to near zero;
4. require the reported reset boundary to advance;
5. reject stale/out-of-order samples;
6. confirm ambiguous weekly resets before notifying.

This detects resets performed elsewhere as soon as the next poll returns the
new snapshot. It cannot prove or enumerate multiple resets that happen entirely
while the monitor is offline.

### Desktop-only task monitoring in the inspected projects

The only demonstrated route is rollout attribution. Both `clawd-on-desk` and
CodexBar inspect `session_meta.originator`/`source`; neither obtains a supported
Desktop surface field from Hook input or a passive Desktop App Server
subscription. The former's recorded originator rename demonstrates that this
would require a compatibility table and unknown-origin fail-closed behavior.

This is a statement about the reviewed community implementations, not the full
current Codex capability surface. Separate official and local-bundle research
found an official Unix-socket App Server transport plus an undocumented Desktop
daemon opt-in. None of the inspected repositories uses or validates that
shared-daemon topology.

### Architectural consequence

The GitHub evidence supplies two proven fallback patterns:

- `clawd-on-desk` for Hook plus rollout task-state reconstruction;
- CodexBar for quota polling and reset-transition detection.

They should not be adopted before testing the newly identified shared-daemon
route. If that spike succeeds, Codex Beacon can use the official state and
quota protocol while limiting private dependency to the Desktop launch
compatibility switch. If it fails, the product must explicitly choose between
reopening ADR-0002 for bounded, read-only rollout parsing or reducing the
task-state promise.

Private Electron IPC, `process_manager`, and SQLite live-state inference should
not be selected: none has comparable public implementation evidence in the
reviewed projects.
