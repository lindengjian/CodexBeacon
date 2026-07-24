# Codex Desktop Task-State Update

Date: 2026-07-24

This note updates the earlier task-state conclusion after checking the current
published App Server documentation, the latest `openai/codex` source, the
installed Codex CLI, and the installed Codex Desktop bundle.

## Updated conclusion

The App Server now has an official local multi-connection transport:

```text
codex app-server --listen unix://
~/.codex/app-server-control/app-server-control.sock
```

The [official App Server documentation](https://developers.openai.com/codex/app-server)
documents:

- stdio as the default transport;
- Unix-socket transport via `--listen unix://` or a custom path;
- WebSocket framing over the Unix socket;
- `thread/loaded/list`;
- `thread/status/changed`;
- `turn/started` and `turn/completed`;
- `waitingOnApproval` and `waitingOnUserInput`;
- final turn states `completed`, `interrupted`, and `failed`.

This means the protocol and local transport are sufficient for Codex Beacon if
Codex Desktop and Beacon connect to the same App Server process.

## Why the first probe returned `notLoaded`

The running Codex Desktop process currently launches its bundled App Server as:

```text
codex -c features.code_mode_host=true \
  app-server --analytics-default-enabled
```

With no `--listen` value, the server uses private stdio. A separately launched
App Server is a different process with a different in-memory loaded-thread
registry. It can read persisted tasks but correctly reports the Desktop-owned
active task as `notLoaded`.

Therefore the earlier negative result does not disprove the App Server state
API; it proves only that two independent servers do not share runtime state.

## Installed Desktop daemon path

The installed Desktop bundle contains a first-party but undocumented switch:

```text
CODEX_APP_SERVER_USE_LOCAL_DAEMON=1
```

Its connection logic does the following on macOS:

1. Require a local host configuration.
2. Require `CODEX_APP_SERVER_USE_LOCAL_DAEMON=1`.
3. Reject the path when forced to a private CLI override.
4. Run `codex app-server daemon version` as a compatibility check.
5. Connect to:

   ```text
   ~/.codex/app-server-control/app-server-control.sock
   ```

6. Fall back to spawning a private stdio App Server if any condition fails.

The installed `codex 0.144.4` binary contains the matching commands:

```text
codex app-server daemon start
codex app-server daemon version
codex app-server proxy
```

The official transport and state protocol are public. The Desktop environment
switch is not present in public documentation and must be treated as a
compatibility adapter, not a stable contract.

## Candidate architecture

For the current personal macOS build:

1. Beacon starts or verifies the managed local App Server daemon.
2. Beacon makes the daemon opt-in available to the Codex Desktop launch
   environment.
3. Codex Desktop connects to the daemon instead of spawning a private stdio
   server.
4. Beacon connects as a second initialized client over the same Unix socket.
5. Beacon reads `thread/loaded/list` and `thread/list` for the initial snapshot.
6. Beacon consumes `thread/status/changed`, `turn/started`, and
   `turn/completed` for exact state updates.
7. Quota reads and `account/rateLimits/updated` use the same connection.

No Hook, rollout parsing, or SQLite polling is required in this architecture.

## Controlled spike result

The reversible test proved:

1. Desktop selects the daemon when relaunched with the opt-in.
2. Desktop UI remains functional through the daemon.
3. A second client initializes without disrupting the Desktop client.
4. The second client sees Desktop-created threads as loaded.
5. It receives global status changes and can distinguish `completed` by
   reading the newest turn after the terminal transition.
6. Server requests remain owned by Desktop; the passive client received none.
7. Deep links still open the Desktop task, with explicit application
   activation required for reliable focus.

The live spike did not deliberately force an approval, user-input question,
failure, or interruption. Their fields remain part of the same official
runtime status/turn schema and should be covered by implementation tests
without manufacturing destructive user activity.

Rollback to the normal private-stdio topology still requires one final Desktop
restart, followed by removal of the temporary launchd job.

## Docs MCP note

`openaiDeveloperDocs` is enabled in local MCP configuration, but this continued
task did not receive its callable tools after restart. A direct MCP HTTP
initialization attempt was rejected by the official endpoint's Vercel
mitigation with HTTP 403. The official published App Server page and the
first-party `openai/codex` source were therefore used as the fallback sources
required by the `openai-docs` workflow.
