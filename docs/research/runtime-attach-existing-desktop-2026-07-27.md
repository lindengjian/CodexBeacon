# 已运行 Codex Desktop 的无重启接入可行性研究

日期：2026-07-27
问题：Beacon 打开时，能否连接**当前已经运行**的 Codex Desktop，而不要求用户重启 Desktop？

## 结论

可以实现「Beacon 随时打开、立即接入」的目标，但有一个不可绕过的前提：当前 Desktop 在启动时就已经选择了**共享 Unix-socket App Server daemon**。

| 当前 Desktop 拓扑 | Beacon 打开后读取当前任务 | 结论 |
| --- | --- | --- |
| 已连接共享 daemon | 可以。Beacon 作为第二个初始化后的只读客户端连接同一 Unix socket。 | 可行、安全，且本机实测通过。 |
| 默认私有 stdio App Server | 不可以把运行中的 Desktop 无损“改接”到 daemon。 | 不应实现为偷偷附着私有文件描述符、读 Electron IPC 或解析私有记录。 |
| 独立新启一个 App Server | 不能得到 Desktop 的实时内存状态；运行中的 Desktop 任务会是 `notLoaded`。 | 不可作为状态真相来源。 |

因此，正确产品策略是：**把共享 daemon 设为 Desktop 的长期、启动前默认拓扑；之后 Beacon 不管理或重启 Desktop，只负责检测并连接。** 对已经以私有 stdio 启动的那一次 Desktop，必须明确显示“本次无法接入；下次 Desktop 启动后自动可用”，或由用户选择一次受控重启。没有一手证据表明存在安全、受支持的热切换 API。

## 一手证据

### 1. 共享 daemon 可以被第二个被动客户端即时连接

官方 App Server 文档将 Unix socket 列为支持的传输：`--listen unix://` / `unix://PATH`，在默认 control socket 上通过 WebSocket HTTP Upgrade 建连；客户端完成 `initialize`、`initialized` 后即可读取通知和请求。[官方 App Server 文档：传输与初始化](https://learn.chatgpt.com/docs/app-server#protocol)

同一份官方文档明确说明：

- `thread/loaded/list` 返回“当前在内存中的任务”；
- `thread/read` 不会订阅任务；
- `thread/status/changed` 在已加载任务的运行时状态变化时发出，包含新状态和 `waitingOnApproval`；
- `thread/turns/list` 可读取持久化回合而无需 resume。

来源：[官方线程 API 文档](https://learn.chatgpt.com/docs/app-server#threads)。本机 bundled CLI `0.146.0-alpha.3.1` 生成的版本专属 schema 同时包含 `thread/loaded/list`、`thread/status/changed`、`waitingOnApproval`、`waitingOnUserInput` 和 `TurnStatus` 的 `completed` / `interrupted` / `failed`（命令：`codex app-server generate-json-schema --out <temp> --experimental`）。

2026-07-27 的只读验证（命令：`node spikes/shared-daemon-observer.mjs --watch-seconds=1`）连接到了现有 socket，读到五个 loaded threads，其中当前 Desktop 根任务的 `source` 为 `vscode`、状态为 `active`；观察者收到零个 server request。这说明同一已运行的共享 daemon 可被 Beacon **立即**被动接入，而不重启 Desktop。验证脚本见 [`spikes/shared-daemon-observer.mjs`](../../spikes/shared-daemon-observer.mjs)。

同次只读检查 `codex app-server daemon version` 返回：

```json
{"status":"running","cliVersion":"0.146.0-alpha.3.1","appServerVersion":"0.146.0-alpha.3.1"}
```

即 socket 当前可用且 client/server 版本相符。

### 2. 默认私有 stdio 不能被事后安全附着

App Server 默认传输是 `stdio://`；官方文档将它定义为默认 JSONL 标准输入/输出传输。[官方 App Server 文档：支持的 transports](https://learn.chatgpt.com/docs/app-server#protocol) 这意味着 Desktop 用默认方式启动时，App Server 的连接端点是其父进程持有的私有 stdio，而不是可发现、可多客户端连接的 Unix socket。

本仓库的初始实测记录了该默认 Desktop 启动方式和结果：另起的 App Server 可以列出持久化任务，却把正在工作的 Desktop 任务报告为 `notLoaded`；也没有可供 companion 附着的 TCP 或 filesystem Unix listener。来源：[`docs/research/local-probe-results.md`](local-probe-results.md) 的“Hook and Desktop runtime state”。

这是状态隔离，不是 Beacon 漏掉一次轮询：`loaded/list` 是**单个 server 进程的内存**视图。另起 server 不会共享 Desktop 私有 server 的 loaded-thread registry，因此无法可靠获取进行中任务、审批或等待输入。

### 3. 现有兼容适配器只能影响下一次 Desktop 启动

仓库的 [`DesktopDaemonCompatibilityAdapter`](../../Sources/CodexBeacon/DesktopDaemonCompatibilityAdapter.swift) 写入用户域 LaunchAgent，并设置私有环境变量 `CODEX_APP_SERVER_USE_LOCAL_DAEMON=1`。其源码注释和 `prepare` 的行为都刻意限定为“*next* Desktop process”，且绝不终止 Desktop，避免丢失用户工作。

这不是推测：对当前安装的 Desktop `26.721.41059` 的一手 bundle 检查显示，`app.asar` 的启动连接分支仅在创建 transport 时读取 `process.env.CODEX_APP_SERVER_USE_LOCAL_DAEMON === "1"`，完成 `codex app-server daemon version` 兼容性检查后才连接 `app-server-control.sock`；条件不满足就创建 stdio transport。该分支没有 runtime reattach/migrate 调用。由于此变量在进程环境中读取，Beacon 后续执行 `launchctl setenv` 只能影响**以后创建的 Desktop 进程**，不能改变已经运行的 Electron 进程。

现有 [`DesktopAppServerMonitor`](../../Sources/CodexBeacon/DesktopAppServerMonitor.swift) 也已将成功标准设为“看到一个非 ephemeral、非 system 的 `vscode` loaded thread”，而非“只要 socket 连上”。这是必要的 fail-closed 保护：一个无关或陈旧 daemon 不能被误当成 Desktop 实时状态。

较早的受控 spike 还证明了这种启动前 opt-in 的正向路径：Desktop 重启后不再生成私有 stdio 子 server，Beacon 作为第二客户端看到了 loaded Desktop task 和 `thread/status/changed`，且没有取得 approval/input 请求的所有权。来源：[`docs/research/shared-daemon-spike.md`](shared-daemon-spike.md)。

`CODEX_APP_SERVER_USE_LOCAL_DAEMON` 是 installed bundle 的私有兼容路径，**没有**出现在官方文档中；它必须继续按 Desktop/bundled CLI 版本严格门控，不能宣传为稳定公开 API。这个边界也已在 [`docs/adr/0002-use-official-local-codex-integration.md`](../adr/0002-use-official-local-codex-integration.md) 记录。

### 4. CLI 新出现的 daemon/remote-control 命令不构成私有 Desktop 热接入

本机 `codex app-server daemon --help` 提供 `start`、`restart`、`enable-remote-control` 等命令；但 `enable-remote-control --help` 的文字限定为“future starts and a currently running **managed daemon**”。`app-server proxy` 同样仅代理到“running app-server control socket”。它们管理的是已经处于 daemon 拓扑的 server，而不是让第三方加入 Desktop 现有的私有 stdio server。

没有官方文档或本机 CLI 帮助声称这些命令能把已运行的 Desktop 私有 stdio App Server 热迁移为共享 daemon。不能从“存在 daemon restart”推论“可以重启或替换 Desktop 正在使用的 server”；那会破坏进行中的任务和请求归属。

## 安全与支持边界

### 可采用

1. Beacon 每次启动先做非破坏性检查：socket 存在、`daemon version` 为 `running`、bundled CLI 与 server 版本相同。
2. 用 Unix-socket WebSocket 建立**第二个**连接，按官方握手初始化；只发 `thread/loaded/list`、`thread/read`、终态后的 `thread/turns/list` 和 quota reads。
3. 仅在实际读取到符合过滤条件的 Desktop root thread 后显示监测可用。对通知只消费，不回复任何 server request，不调用 `thread/resume`。
4. 首次安装/升级兼容适配器后，将其保留到用户主动关闭监测；它只为**未来的** Desktop 启动设置共享 daemon。此后用户关闭再打开 Beacon 不应再需要重启 Desktop。

### 不应采用

- 复制、复用或注入 Desktop 与私有 stdio child 之间的 socketpair/file descriptor；这不是公开 transport，且会越过 Desktop 的会话与请求所有权。
- 扫描 Electron IPC、内存、私有 ASAR 协议、rollout/JSONL/SQLite 来拼实时状态；这些不是稳定接口，并且无法保证审批、等待输入和终态正确性。
- 在 Beacon 打开时执行 `daemon restart`、杀掉 App Server 或强制退出 Desktop；它们可能中断当前 turn，超出“被动状态观察”的授权范围。
- 将独立启动的 App Server 的 persisted `thread/list` 当作实时 Desktop 状态；一手 probe 已明确显示这个拓扑给出 `notLoaded`。

## 建议的实现方向

1. **保留现有共享-daemon 架构，但拆开“配置未来 Desktop”和“连接当前 daemon”两个状态。** Beacon 每次打开优先连接、验证并开始观察；验证成功就直接恢复黄/绿状态，不显示重启提示。
2. **把“需要重启”变成一次性的配置状态，而不是常态文案。** 仅当不存在有效 daemon，或能连 daemon 但五秒内没有 Desktop loaded-thread 证据时，显示：
   - “当前 Codex 以私有连接运行，本次无法安全读取实时任务。”
   - “已为下次 Codex 启动准备共享连接；下次启动后 Beacon 会自动接入。”
   不能承诺无需 Desktop 重启即可接入这一轮已私有启动的任务。
3. **将无重启体验定义为稳态验收标准。** 测试应先让 Desktop 在适配器已安装时启动；随后反复退出/打开 Beacon，断言每次均可在数秒内读到同一 loaded Desktop thread，且不调用 resume、不出现入站 server request。
4. **继续版本门控并 fail closed。** 若 Desktop 更新后 daemon 版本、socket 协议、`vscode` 来源观察或被动多客户端行为任一不成立，显示红灯“监测不可用”，不要退回私有解析。

## 对本次问题的直接回答

对于**当前已经在共享 daemon 上运行**的 Codex Desktop，Beacon 打开时即可连接——本机只读实测已证实。对于**当前已经以私有 stdio 运行**的 Codex Desktop，不重启就让 Beacon 可靠读取实时状态，目前没有可采用的一手证据；应把这次限制坦诚呈现，并通过“启动前持久启用共享 daemon”使它只发生一次，而非每次启动 Beacon 都发生。
