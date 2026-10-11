# 原生彩带最小包装提案（待协调者批准）

C1 的扩展内 `open("raycast://confetti")` 仍出现确认框，由协调者取消。正式路径不采用该 URL，不改变 Raycast 安全设置。本提案只记录实现方案，尚未引入 renderer。

## 固定依赖

采用 [ConfettiSwiftUI 3.0.0](https://github.com/simibac/ConfettiSwiftUI/tree/9ae5bc2ce2149980884d4612321c3a266d6bf82c)，commit `9ae5bc2ce2149980884d4612321c3a266d6bf82c`。只保留下面的源文件、包说明和 MIT 许可证；不引入上游测试、示例、图片或远程 SwiftPM 解析。已从该 commit 下载源码到临时目录并读取，没有运行。

| 文件 | 原始 SHA-256 |
| --- | --- |
| `LICENSE` | `7f5138952ef2a5c9fc4ef15d77d8449f0b20f0da041ebc493153febefa9daa4d` |
| `Package.swift` | `233f1cb5aada18f131991a61bbc83dd713b2213ee24202c098bdd52e9cd505e3` |
| `Sources/ConfettiSwiftUI.swift` | `3fbb7f0c83aae0e5db351e1b43801134e98cd45b143891bb92078be5433cb0e1` |
| `Sources/View+ConfettiCannon.swift` | `3ad23c43610a172955a79359ad502c09340ae52c60fc00b280642bf736d6ac02` |
| `Sources/Shapes/RoundedCross.swift` | `785e9ffaf63e43b04b26d7a2e5ec2de5323f23be6e44794393812005c74a0e8c` |
| `Sources/Shapes/SlimRectangle.swift` | `d5731df200566f3a5c4776c82a2beb55eafb1fc26905d9ba352a4974031f214e` |
| `Sources/Shapes/Triangle.swift` | `8b161bbdbfbbaf8c4f34188d9c59a7b05a3c58bd0fbd1614d2b1713e057d78cf` |

MIT，Copyright (c) 2020 Simon Bachmann；完整许可证随 vendored 源码和最终 assets 分发。`SOURCE.json` 保存上游 URL、commit 和全部原始摘要。

## 包装与视觉

新增独立 `likeit-confetti` 可执行 helper，AppKit + SwiftUI，不改变音乐 controller。启动时检查 Reduce Motion，取得当前鼠标位置所在的 `NSScreen`，固定该屏幕 frame；无匹配屏幕就退出。进程使用禁止激活策略；透明无边框 `.nonactivatingPanel`，不能成为 key/main window，`ignoresMouseEvents=true`，无阴影，`hidesOnDeactivate=false`，不调用 activate 或 makeKey。使用 `canJoinAllSpaces`、`fullScreenAuxiliary`、`ignoresCycle`，窗口层级为 statusBar；实际 Space / 全屏行为由 reviewer 验证。

NSHostingView 放两个 cannon：左右边缘、距顶部约 72% 高度，各 60 个彩色纸片（square/slimRectangle/circle），左 35–75°、右 105–145°，向内上方喷射。半径取 `min(width * 0.65, height * 0.9)`，下落距离取 `height * 0.45`；仅一次 trigger，`repetitions=1`、`hapticFeedback=false`、`fadesOut=true`。不播放声音。

## 最小上游补丁与退出

原库 `ConfettiConfig` 将爆发时长设为 `radius / 1300`、下落时长设为 `(rainHeight + radius) / 200`，大屏下会超过目标。拟只在临时构建副本中把这两行分别改为固定 `0.45` 秒和 `1.6` 秒，保持距离独立；原始 vendored 源码不改。构建脚本要求每个原表达式恰好出现一次，否则失败，并记录补丁后源码摘要。其余粒子逻辑保持上游原样。

首帧安装后只触发一次；约 2.1 秒开始窗口淡出，2.4 秒关闭退出。进程启动立即设置独立于主线程的 2.9 秒硬退出 watchdog，即使 GUI 主线程卡住，也由进程退出撤走窗口。提前失败退出同样释放资源。上游的旋转 `repeatForever` 只存在于短命视图中，不形成常驻任务。系统 Reduce Motion 切为开启时立即结束显示。

## 有界启动、并发与集成

helper 使用 supportPath 下独立固定 inode 的 `confetti.lock`，`flock(LOCK_EX | LOCK_NB)`；已在显示就立即跳过，不排队、不延长上一轮。锁不删除，文件描述符随进程退出释放，和音乐锁完全分离。

TypeScript adapter 启动 helper 后等待一行 `started` / `skipped`，启动等待最多 1 秒，坏响应、输出超限、退出错误或超时终止子进程，不重试。`started` 后脱离 Node 生命周期，由 helper 自己在上述硬期限退出；`celebrate()` 表示有界启动尝试。此时音乐 session 已在 finally 中关闭，最终 status 已落实，HUD 已显示。新原生预览仍与音乐完全隔离，供 reviewer 独占执行，最终移除预览 manifest 项。

构建复用 `scripts/build-native.py`：校验原始源摘要 → 在临时目录应用上述两行补丁 → `swiftc` 编译 helper 和五个 Swift 源文件，链接 AppKit/SwiftUI，目标 macOS 13 的 arm64/x86_64 → lipo → ad-hoc 签名及校验 → BUILD.json 记录 wrapper/构建脚本/补丁后源码/产物摘要与完整命令。运行时不下载、不编译、不增加隐私授权。

待确认：此依赖子集、两行时间补丁、窗口策略及启动/生命周期方案。视觉、当前屏幕、键鼠穿透、焦点/Space、并发和清理仍需真实验收；源码和编译成功不能替代。
