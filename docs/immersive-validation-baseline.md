# 沉浸桌面冻结基线（协调者）

日期：2026-10-11；产品起点 `7f340d5`。首次开发尚未派遣。

- 既有三个冻结清单共16项全部 SHA-256 一致；既有68条 Node测试全通过，原输出 `/tmp/likeit-immersive-existing.tap`。
- 新 `node --test acceptance/immersive-desktop.test.mjs`：3个顶层检查均红，原因分别为缺少新菜单、缺少独立桌面动效偏好、缺少 `native/ImmersiveCore.swift`。退出码1，输出 `/tmp/likeit-immersive-red.tap`。没有跳过或伪造实现。
- 原生驱动预先固化54个行为断言：歌词12、时钟7、匹配14、换曲状态6、音频12、动效3。驱动用自己创作的短文本与合成PCM，不触碰音乐app或权限。
- 冻结前以临时接口桩单独做 Swift typecheck，发现测试辅助函数 default argument 的 MainActor 推断编译问题，改成直接构造值后 typecheck 成功。该修正发生在产品实现前，不改变行为预期。接口桩只位于 `/tmp/likeit-immersive-interface.swift`，不是产品代码、不是通过行为验收的证据。
- 新测试不证明 process tap、TCC、实际歌词同步、UI清晰度或极简退出；这些必须在正式构建与真实路径单独验证。开发者 build/lint 与实际测试结果分开记录。

冻结内容见 `docs/immersive-acceptance.sha256`。基线 commit SHA 在新开发会话派遣消息提供。开发者实现后仅修产品；若测试本身与用户需求矛盾，先报告协调者，按原有契约勘误流程处理。
