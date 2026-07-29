# Codex Beacon

<p align="center">
  <img src="docs/images/codex-beacon-icon-glass.png" width="256" height="266" alt="Codex Beacon 图标">
</p>

[English README](README.en.md)

Codex Beacon 是一个原生 macOS 工具，用类红绿灯展示 Codex Desktop 任务的聚合状态，并在边缘额度刻度上显示当前账户额度。

它采用保守策略：如果缺少足够且及时的 Desktop 运行时证据，就显示 **监测不可用**，绝不会误报为“空闲”。

## 下载

[下载 Codex Beacon 1.0.6](https://github.com/lindengjian/CodexBeacon/releases/tag/v1.0.6)

Release 页面提供 Apple Silicon DMG 和对应的 SHA-256 校验值。

### 系统要求

- macOS 15 或更高版本
- Apple Silicon Mac
- 已在本机安装 Codex Desktop

### 安装

1. 下载并打开 `CodexBeacon-1.0.6-arm64.dmg`。
2. 将 **Codex Beacon** 拖入 **Applications** 文件夹。
3. 在 Applications 中打开 Codex Beacon；如 macOS 要求确认打开，请按系统提示操作。

首次启动时，Beacon 会检查本机 Codex Desktop 集成、请求通知权限，并提供“登录时启动”。随后它以 accessory 应用方式运行，不显示 Dock 图标或菜单栏项目。

### npm（面向开发者）

如果你已安装 Node.js 20 或更新版本，也可在 npm 发布后使用：

```sh
npx @lindengjian/codex-beacon install
```

该命令会先验证包签名，再将 App 安装到 `~/Applications/CodexBeacon.app` 并启动它；不会绕过 macOS 的安全确认。全局安装及后续管理也可使用：

```sh
npm install -g @lindengjian/codex-beacon
codex-beacon doctor
codex-beacon uninstall
```

## 它展示什么

| 空闲 | 工作 | 已完成 |
| :---: | :---: | :---: |
| ![空闲状态](docs/images/status-idle.png) | ![工作状态](docs/images/status-working.png) | ![已完成状态](docs/images/status-completed.png) |
| 三个任务灯均熄灭。 | 琥珀色灯缓慢呼吸。 | 绿色灯常亮，直到完成被确认。 |

| 状态 | 信号 | 含义 |
| --- | --- | --- |
| 监测不可用 | 红灯常亮 | Desktop 监测证据缺失、过期或不兼容。 |
| 审批 | 绿灯闪烁 | 任务需要你的审批、授权或回答。 |
| 工作 | 琥珀灯呼吸 | 至少一个任务正在运行。 |
| 已完成 | 绿灯常亮 | 至少一个成功完成尚未确认。 |
| 空闲 | 所有灯熄灭 | 没有审批、工作中或未确认完成的任务。 |

多个任务处于不同状态时，以上顺序决定主状态。若 macOS 开启 **减少动态效果**，所有动画都会停止；“审批”会显示为双层绿色圆环，以便与“已完成”的实心绿灯区分。

## 功能

- 仅监测 **Codex Desktop 任务**；不监测 CLI、IDE 扩展或远程任务。
- 以小型浮动面板常驻在普通窗口上方，跨 Space 与符合条件的全屏应用可见，可吸附到屏幕边缘；不创建 Dock 图标或菜单栏项目。
- 单击后打开或聚焦相关 Codex 任务，并确认当时已有的完成状态。
- 悬停可查看任务聚合计数、额度窗口、重置时间、最后更新时间与监测错误；任务标题默认隐藏。
- 自动选择当前最短的额度窗口；不假定固定存在五小时或每周额度。
- 检测到可确认的额度重置时，发送通知、可选声音、五秒边框提示和临时消息；相邻重置会合并为一条提醒。
- 支持标准尺寸（`62 × 229 pt`）、紧凑尺寸（`24 × 88 pt`）、可设置的全局快捷键、登录时启动，以及为“审批”“已完成”“额度重置”分别配置声音。

## 未来支持

- [ ] Windows 系统支持。
- [ ] 应用浅色与深色模式切换。
- [ ] 自定义主题与换肤。

## 使用方式

- **单击**：优先打开或聚焦等待审批最久的任务；否则选择已完成或工作中的任务，并确认已有完成。
- **悬停**：查看状态计数、额度窗口、重置时间、最后更新时间与可用性错误。
- **拖动**：拖到任意屏幕边缘。左右边缘为纵向，上下边缘为横向。
- **右键**：打开设置、临时隐藏/显示或退出。
- 默认全局快捷键为 **Control + Option + Command + C**，可在设置中替换。

## 本地集成

Beacon 是本地 Codex App Server 的被动观察者：不会恢复或修改任务、回复审批/输入请求，也不会读取私有转录记录。若设置中显示“监测不可用”，请运行诊断；仅在提供该选项时选择“修复集成”，随后完全退出并重新打开 Codex Desktop，再次运行诊断。

你可以随时在设置中恢复默认 Desktop 集成。

## 隐私

Beacon 只与本地 Codex App Server 通信；不包含遥测、崩溃报告、云同步或自动更新检查。

本地诊断日志只保留连接生命周期与协议/状态元数据，不包含原始 App Server JSON、任务 ID 或标题、账户字段或本地路径。仅在你于设置中明确导出带时间戳的副本后，日志才会离开本机。

## 开发

开发需要 Xcode 16 或更高版本。在仓库根目录执行：

```sh
# 运行测试
swift test

# 组装 release 应用包，产物位于 .build/CodexBeacon.app
./scripts/build-app.sh

# 运行 npm 安装器测试
npm test --prefix npm

# 构建并检查即将发布的 npm 包
npm run pack:check --prefix npm
```

## 了解更多

详细的兼容性检查与 macOS 窗口矩阵见[验收记录](docs/acceptance/first-local-milestone.md)；产品细节和范围见 [docs/PRODUCT.md](docs/PRODUCT.md)。
