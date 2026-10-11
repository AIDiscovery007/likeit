# Likeit 动效独立配置迭代

2026-10-11。起点 `d33e6a6`。用户明确选择“跟随系统／始终播放／关闭”。这条新指令替代上一轮 C04 对所有情况一律遵守系统设置的限制；旧冻结资料不重写。

## 用户行为

Raycast Settings → Extensions → Likeit → **收藏成功动效**。使用一个 dropdown 偏好 `motionMode`：`system`（跟随系统，默认）、`always`（始终播放）、`off`（关闭）。移除旧 `successConfetti` checkbox，避免两个控制互相冲突。此次是未发布本地开发版本的设置升级，不承诺迁移已移除 checkbox 的历史值；安装后采用新的默认设置，在 README 明示。未知值或偏好读取失败按关闭处理。

“始终播放”只允许 Likeit 在确认新增喜欢后发射彩带，不更改 macOS 设置、不影响其他 app，也不绕过收藏成功判定、独立锁和退出期限。只有明确选择该模式才忽略系统 Reduce Motion。跟随系统仍只在明确读取为 false 时播放，包含原生进程发射前的复查和显示期通知；始终播放的原生窗口不因系统 Reduce Motion=true 或相关通知被取消。关闭模式不读策略、不启动 renderer。

Raycast 原生 dropdown 已有官方支持：[Manifest preference properties](https://developers.raycast.com/information/manifest#preference-properties)。不新增设置框架、全局配置文件或运行时依赖。

## 接口与兼容

扩展现有 `presentResult` 的第二参数为 `boolean | "system" | "always" | "off"`。旧 boolean 调用继续代表 true→跟随系统、false→关闭，以保留原 18 个冻结回归用例及其语义；正式入口只传新三态偏好。无效运行时输入保守关闭。

`FeedbackPort.celebrate(mode: "system" | "always")` 接收明确的渲染策略；不把上层检查等同于原生许可。`celebrate(nativeDirectory, supportPath, mode = "system")` 将该策略传入原生 helper。原生 CLI 保留单个绝对锁路径调用的默认 system 行为，另允许第二参数 system / always；其他值、额外参数都跳过。off 不应产生 helper 进程。

正式流程保持 session close 与失败映射 → 原 HUD → 可选反馈。不得扩大音乐操作、重试收藏、修改原核心/原音乐锁。动画错误不改变结果。

## 最小闭环

| 闭环 | 开发者 | 协调者 |
| --- | --- | --- |
| M0 | 等待新基线 | 先提交 BDD、测试、红灯与摘要；旧 46 条保持不变 |
| M1 | 三态 dropdown、反馈编排、正式入口与文档；build/lint，提交 | 新旧冻结用例与入口检查 |
| M2 | TS 参数透传、Swift 对明确 always 的支持；重建双架构与摘要，提交 | 参数、默认/无效策略、系统模式与 always 的独立预览、锁/进程清理 |
| M3 | 清理临时预览，提交 implementation-complete | 固定提交双轴 review、注册最终版、记录已验证与剩余范围 |

M1/M2 可顺序在同一实现提交交付，但需报告每项边界。可临时添加与音乐隔离的 Raycast no-view 预览命令，带显式 dropdown 参数 system / always / off，使用同一反馈与 renderer，HUD 必须标记“预览（不操作音乐）”；不得进入正式收藏入口或输出虚假的收藏成功提示。该预览不修改持久偏好，协调者用其验证三种选择，最终移除。显示动画已经是本次明确允许的模式行为，不必改变全局 Reduce Motion。

## 验证范围与分工

新增 `acceptance/motion-mode.test.mjs` 固化三态语义、默认/可发现配置、无效输入、非 liked 结果、异常保留 HUD 和旧 boolean 兼容。旧收藏 28 条及上一轮反馈 18 条和两份冻结清单均保持不变。本轮单独冻结清单；开发者不写改删跑测试。

协调者另外验证正式入口传递所选模式、关闭失败不庆祝、原生默认/坏参数仍保守、always 不被第二层 Reduce Motion 拦截、system 保持通知取消、独立预览无音乐、可见双侧方向/透明/焦点/输入/屏幕/锁/时限。无实际证据的场景仍标待验，不以 started 代替像素。

开发继续原会话 `01a12995-4d3b-7bf3-82da-c9181687b34b`，effort high。只本地提交，不 push/发布；不控制音乐或运行预览，有疑问咨询协调者。新用户指令已经授权三态产品行为，无须再申请旧 C04 的例外。
