# Use official local Codex integration points

The app will read account quota through the documented Codex App Server protocol. Task state must come from a supported Codex Desktop runtime-state transport that exposes the App Server's thread status, turn completion, approval, and request-user-input semantics.

A global lifecycle Hook is not an authoritative task-state transport. Its public input cannot identify the Desktop surface, does not expose request-user-input waiting, and does not distinguish completed, failed, and interrupted turns. A separately launched App Server is also not equivalent to the Desktop-owned App Server: live probes showed Desktop tasks as persisted but `notLoaded`, while the default Desktop server was reachable only through private parent-process stdio.

The official App Server supports a Unix-socket daemon that can accept local clients. The installed Desktop bundle also contains an undocumented opt-in that makes Desktop use that daemon. A live spike proved that Desktop and a second passive client can share the daemon: the passive client saw the current Desktop thread as loaded, received `thread/status/changed`, and confirmed the previous turn's `completed` status without resuming the thread or receiving server requests.

Codex Beacon will therefore use the official App Server state and quota protocol over the shared Unix socket. It will treat `CODEX_APP_SERVER_USE_LOCAL_DAEMON=1`, bundled-CLI discovery, and Desktop restart orchestration as a version-gated compatibility adapter. If that adapter is unavailable or the App Server versions are incompatible, Beacon fails closed to unavailable rather than parsing private transcript, rollout, database, or Electron IPC formats.

Beacon will not call `thread/resume` merely to observe a task. It will build the initial snapshot with `thread/loaded/list` and `thread/read`, ignore ephemeral/system threads, consume global `thread/status/changed` notifications, and read the newest turn after a terminal transition to distinguish `completed` from `failed` or `interrupted`.
