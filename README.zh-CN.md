# Codex Beacon

[English README](README.md)

Codex Beacon 是一个原生 macOS 工具，用紧凑、非激活的三色状态灯展示 Codex Desktop 任务的聚合状态，并在边缘额度刻度上显示当前账户额度。

它采用保守策略：如果缺少足够且及时的 Desktop 运行时证据，就显示 **监测不可用**，绝不会误报为“空闲”。

## 状态一览

| 空闲 | 工作中 | 已完成 |
| :---: | :---: | :---: |
| ![空闲状态](docs/images/status-idle.png) | ![工作中状态](docs/images/status-working.png) | ![已完成状态](docs/images/status-completed.png) |
| 三个任务灯均熄灭。 | 琥珀色灯缓慢呼吸。 | 绿色灯常亮，直到完成被确认。 |

| 状态 | 信号 | 含义 |
| --- | --- | --- |
| 监测不可用 | 红灯常亮 | Desktop 监测证据缺失、过期或不兼容。 |
| 等待你 | 绿灯闪烁 | 任务需要你的审批、授权或回答。 |
| 工作中 | 琥珀灯呼吸 | 至少一个任务正在运行。 |
| 已完成 | 绿灯常亮 | 至少一个成功完成尚未确认。 |
| 空闲 | 所有灯熄灭 | 没有等待、运行中或未确认完成的任务。 |

多个任务处于不同状态时，以上表的顺序决定主状态。若 macOS 开启 **减少动态效果**，所有动画都会停止；“等待你”会显示为双层绿色圆环，以便与“已完成”的实心绿灯区分。

## 功能

- 仅监测 **Codex Desktop 任务**，不监测 Codex CLI、IDE 扩展或远程任务。
- 以浮动面板常驻在普通窗口上方，跨 Space 与符合条件的全屏应用可见，可吸附到屏幕边缘；不创建 Dock 图标或菜单栏项目。
- 单击 Beacon 会打开或聚焦相关 Codex 任务，并确认当时已有的完成状态。
- 悬停可查看任务聚合计数、额度窗口、重置时间、最后更新时间与监测错误。任务标题默认隐藏，可在设置中开启。
- 自动选择当前最短的额度窗口；不假定固定存在五小时或每周额度。
- 检测到可确认的额度重置时，发送 macOS 通知、可选系统声音、五秒边框提示和临时消息；相邻重置会合并为一条提醒。
- 支持标准尺寸（`62 × 229 pt`）、紧凑尺寸（`24 × 88 pt`）、可设置的全局快捷键、登录时启动，以及为“等待你”“完成”“额度重置”分别配置声音。

## 环境要求

- macOS 15 或更高版本
- Apple Silicon
- Xcode 16 或更高版本
- 已在本机安装 Codex Desktop

项目是 Swift Package，不依赖第三方包。

## 构建、运行与测试

```sh
# 测试
swift test

# 使用 SwiftPM 构建并运行
swift build --arch arm64
swift run CodexBeacon

# 构建应用包
./scripts/build-app.sh
open .build/CodexBeacon.app
```

首次启动会显示设置窗口：检查本机 Codex Desktop 集成、请求通知权限，并默认提供“登录时启动 Beacon”。完成后，Beacon 以 accessory 应用方式运行，没有 Dock 图标或菜单栏入口。

## Codex Desktop 集成

Beacon 是本地 Codex App Server 的被动观察者。要精确读取正在运行的 Desktop 状态，Codex Desktop 与 Beacon 必须事先连接到同一个 Unix-socket App Server daemon。Beacon 作为第二个已初始化客户端连接，读取已加载任务、状态通知、最近终态回合与额度快照；它不会恢复或修改任务、回复服务端审批/输入请求，也不会解析私有转录记录。

Codex Desktop 默认使用私有 stdio App Server，启动后无法被安全地热接入。若设置中显示监测不可用：

1. 在 Beacon 右键菜单打开 **设置**，运行诊断。
2. 仅在提供该选项时选择 **修复集成**。
3. 保存工作后，完全退出并重新打开 Codex Desktop。
4. 再次运行诊断。Beacon 只有实际看到已加载的 Desktop 运行时任务，才会离开红色“监测不可用”状态。

修复操作仅写入 Beacon 自己带标签的用户级 LaunchAgent 和一项供下次 Desktop 进程使用的兼容性设置；它绝不会关闭 Desktop 或中断任务。该路径严格按版本门控：内置 Codex CLI 不受支持或版本不匹配时，Beacon 会保持监测不可用，而不会使用不安全的回退方式。

如需恢复 Codex Desktop 默认的私有 App Server 拓扑，请在设置中选择 **恢复默认 Desktop 集成**，完全退出 Desktop 后重新打开。构建应用包后，也可执行：

```sh
.build/CodexBeacon.app/Contents/MacOS/CodexBeacon --rollback-shared-daemon
```

## 使用方式

- **单击**：优先打开/聚焦等待最久的任务；否则选择已完成或工作中的任务，同时确认已有完成。
- **悬停**：查看状态计数、额度窗口、重置时间、最后更新时间与可用性错误。
- **拖动**：拖到任意屏幕边缘。左右边缘为纵向，上下边缘为横向；断开显示器时，位置会安全迁移到主显示器。
- **右键**：打开设置、临时隐藏/显示或退出。
- 默认全局快捷键为 **Control + Option + Command + C**，可在设置中替换。

## 隐私与诊断

Beacon 只与本地 Codex App Server 通信；不包含遥测、崩溃报告、云同步或自动更新检查。

本地诊断日志位于：

```text
~/Library/Application Support/CodexBeacon/task-monitoring-diagnostic.txt
```

日志只保留连接生命周期与协议/状态元数据，不包含原始 App Server JSON、任务 ID 或标题、账户字段或本地路径。仅在你于设置中明确导出带时间戳的副本后，日志才会离开本机。

## 项目结构

```text
Sources/CodexBeaconCore/  状态聚合、额度解析、位置计算与渲染规则
Sources/CodexBeacon/      AppKit/SwiftUI 界面、App Server 连接、首次设置、设置与诊断
Tests/                    核心场景测试与 macOS 集成边界测试
docs/                     产品规格、验收记录、架构决策与调研
scripts/build-app.sh      生成应用包
```

详细的兼容性检查与手工 macOS 窗口矩阵见[验收记录](docs/acceptance/first-local-milestone.md)；产品细节见 [docs/PRODUCT.md](docs/PRODUCT.md)。

## 范围与限制

当前范围只支持 Apple Silicon macOS。它不会聚合多个账户，不监测 CLI/IDE/远程任务，不保存任务历史，不控制任务，也不报告每个任务的上下文用量；同时不承诺覆盖锁定屏幕、安全面板等 macOS 受保护界面。
