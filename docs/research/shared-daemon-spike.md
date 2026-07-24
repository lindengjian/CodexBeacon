# Shared App Server Daemon Spike

Date: 2026-07-24

## Objective

Prove whether Codex Desktop and a passive Codex Beacon client can use one
official Unix-socket App Server without disrupting Desktop behavior.

## Pre-restart result

The installed versions are:

- PATH CLI: `codex-cli 0.144.4`;
- Codex Desktop bundled CLI: `codex-cli 0.146.0-alpha.3`.

`codex app-server daemon start` cannot be used on this machine because it
requires the installer-managed binary at:

```text
~/.codex/packages/standalone/current/codex
```

Starting the bundled server directly works:

```text
/Applications/ChatGPT.app/Contents/Resources/codex \
  -c features.code_mode_host=true \
  app-server \
  --listen unix:// \
  --analytics-default-enabled
```

The control socket was created at:

```text
~/.codex/app-server-control/app-server-control.sock
```

`codex app-server daemon version` reported matching bundled client and server
versions, both `0.146.0-alpha.3`.

The passive observer successfully:

- completed a WebSocket upgrade over the Unix socket;
- initialized a second App Server client;
- called `thread/loaded/list`;
- called `thread/read` without resuming or subscribing;
- called `thread/list`;
- called `account/rateLimits/read`;
- received the logged-in Plus account's current dynamic quota window;
- exited with zero incoming server requests.

The observer is:

```text
spikes/shared-daemon-observer.mjs
```

## Temporary launch setup

To keep the socket server alive while Codex Desktop restarts, the spike uses a
transient user launchd job:

```text
com.codexbeacon.shared-app-server
```

The following environment value is present in the user launchd domain for the
next Codex Desktop process:

```text
CODEX_APP_SERVER_USE_LOCAL_DAEMON=1
```

The already-running Desktop remains connected to its original private stdio
server. A full Desktop quit and relaunch is now required.

## Rollback

After the spike:

```text
launchctl unsetenv CODEX_APP_SERVER_USE_LOCAL_DAEMON
launchctl remove com.codexbeacon.shared-app-server
```

The launchd job and opt-in are temporary and do not modify Codex task data or
the user's Codex configuration file.

## Post-restart checks

1. Verify Desktop no longer spawns its own `app-server` child.
2. Verify the shared daemon reports at least the Desktop's current loaded task.
3. Read the active thread status without resuming it.
4. Observe working, approval, user-input, completed, interrupted, and failed
   transitions.
5. Confirm the observer receives no server request requiring a response.
6. Confirm task deep links still focus the correct Desktop task.
7. Roll back the temporary launch environment and launchd job.

## Post-restart result in progress

After fully quitting and reopening Codex Desktop:

- Desktop PID changed and remained a direct child of launchd.
- No private stdio `app-server` child was created by Desktop.
- The shared Unix-socket App Server remained running as a separate launchd
  process.
- `thread/loaded/list` returned the current visible Desktop task.
- `thread/read` returned the current task as:

  ```json
  {
    "name": "设计极简 Codex 状态工具",
    "source": "vscode",
    "status": {
      "type": "active",
      "activeFlags": []
    }
  }
  ```

- A second initialized client read the state and quota without resuming or
  subscribing to the thread.
- The second client received zero server requests.

This proves the Desktop daemon opt-in and shared loaded-thread state. It also
confirms that Desktop still labels its task source as `vscode`; Beacon must not
filter loaded tasks using `sourceKinds: ["appServer"]`.

The remaining live-event check uses only `thread/loaded/list` and `thread/read`
at a short interval. This preserves the Desktop client's ownership of turn
events and approval requests while still exposing exact runtime status.

## Live transition result

The passive client received the current Desktop task's global status
notification without calling `thread/resume`:

```json
{
  "method": "thread/status/changed",
  "params": {
    "status": { "type": "idle" }
  }
}
```

A subsequent read of the newest turn returned:

```json
{
  "status": "completed",
  "error": null
}
```

After the next user message, the same client received:

```json
{
  "method": "thread/status/changed",
  "params": {
    "status": {
      "type": "active",
      "activeFlags": []
    }
  }
}
```

This proves the working-to-completed-to-working path. Production does not need
continuous high-frequency thread polling: use a loaded-thread snapshot on
connect, consume global status notifications, and read the newest turn after a
terminal transition.

The shared daemon also exposes Desktop internal threads. The observed internal
rows were `ephemeral: true` with `threadSource: "system"`. They must be excluded
from the user-task aggregate. User-visible root tasks were non-ephemeral.

## Deep-link result

Opening `codex://threads/<thread-id>` through the URL handler alone did not
reliably take focus from another frontmost application in this run. Explicitly
activating `/Applications/ChatGPT.app` while delivering the same URL did focus
Codex. The click implementation should therefore use AppKit to activate the
running `com.openai.codex` application and then open the documented task URL,
rather than relying on a bare URL open for focus behavior.

## Rollback result

The temporary opt-in was removed before a final Desktop restart. After that
restart:

- Desktop again spawned its normal private stdio App Server child;
- `CODEX_APP_SERVER_USE_LOCAL_DAEMON` was absent from the user launch
  environment;
- the temporary `com.codexbeacon.shared-app-server` launchd job was removed;
- the Unix control socket was gone;
- the zero-byte startup lock and now-empty control directory created by the
  spike were removed;
- the current Codex task continued normally on the restored default topology.

No Codex configuration, authentication, transcript, task data, Hook, or account
quota was modified by the spike.
