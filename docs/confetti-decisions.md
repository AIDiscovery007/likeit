# 彩带迭代决策记录

## 2026-10-11 · C1 内置 URL 路径不采用

固定探针提交：`65fb5657a66283898af6941de36c14b0db1b7b37`。协调者已审查其唯一行为：no-view 命令中 `await open("raycast://confetti")`，没有音乐调用、HUD 或隐藏参数。

协调者将该提交隔离归档并运行 `npm run dev`，新旧冻结清单均一致。实际在 Raycast 搜索并运行 **Preview Confetti (Development)** 后，再次出现 **Request to run Confetti**，包含 Run Command / Always Run Command / Cancel；提示命令从 Raycast 外部触发。协调者选择 Cancel，没有播放第二轮彩带，也没有改变安全设置。

因此该内部调用路径仍不符合 C06 的“无额外确认”。这个结论不依赖 URL 的成功返回，也不尝试跳确认参数或永久授权绕过。旧的单次外部预览仅用作双侧视觉参考。

## 下一步

进入计划中的原生备选评估：固定 ConfettiSwiftUI 3.0.0 MIT 源码、透明非激活 NSPanel、独立短生命周期 helper。开发者先报告最小包装方案、使用的精确文件/摘要、必要的上游改动及构建方式；协调者确认后再做依赖该方案的实现。C2 的纯反馈与 Reduce Motion 读取可继续。

产品契约、18 个新反馈用例和旧 28 个收藏用例均不修改。预览本身不读写音乐；真正的新样本收藏和可视验收仍由协调者安排。

## C2 反馈决策复核

固定提交 `604dfb21b8cc71de26946f4842b5e8a82ade8614` 的独立归档中，新 18 条加旧 28 条共 46/46 通过；新旧冻结摘要均匹配。两条独立 review 未发现可行动缺陷。反馈先显示原 HUD，仅在最终 liked、开关开启、Reduce Motion 明确 false 时启动一次；策略或渲染错误不会改写音乐结果。正式入口尚未连接，这是本闭环的预期状态。

## C3 原生包装方案批准

协调者已审查 `fc9ea069262fa5b8c45b03ea85ca2a8734db1d08` 的 `confetti-native-proposal.md`，并直接核对固定上游的发射次数、坐标与时长源码。批准所列 5 个 Swift 源、Package.swift 和 MIT LICENSE 子集、原样 vendoring，以及仅在构建临时副本内将两处时长改为 0.45 秒和 1.6 秒。原文件与补丁结果必须分别记录摘要，匹配不到唯一原表达式时构建失败。

批准独立 AppKit/SwiftUI helper、禁止激活的非 key/main 透明 NSPanel、鼠标穿透、鼠标所在屏幕、左右各 60 个纸片、单次 trigger 与 repetitions=1、无声无触觉、2.1 秒淡出/2.4 秒关闭/启动起 2.9 秒硬退出、Reduce Motion 复查和变更时终止。该上游的循环是 `0..<repetitions`，因此值 1 表示单轮。

独立固定 inode 的非阻塞锁应覆盖整个显示生命周期，和音乐锁分离；拒绝符号链接、不向其他进程继承、不删除锁文件。TS 启动等待、输出和错误处理有界；started 是窗口已安装并提交显示后的启动确认，不代表真实像素/完整动画已经验收。坏响应、超时或启动错误不重试。启动后的 helper 由硬期限收尾，不能依赖 Raycast Node 一直存活。

这是实现方案批准，不是动画验收通过。坐标方向、真实透明度、焦点、全屏/Space、多屏、输入穿透、减少动态效果以及无残留窗口仍需 reviewer 实测；编译成功与 started 不得替代这些证据。
