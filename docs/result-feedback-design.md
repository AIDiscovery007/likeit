# 收藏后的可选反馈

`src/result-feedback.ts` 的 `presentResult` 只编排反馈，不导入 Raycast、不执行进程、不读写音乐。先等待原状态 HUD 呈现；仅 `liked` 且开关开启时读取 Reduce Motion，只有明确 `false` 才调用一次 `celebrate`。策略读取与动画的同步异常、Promise 拒绝均在可选反馈边界消化，不重发 HUD、不重试或改变音乐结果。

Raycast 扩展偏好 `successConfetti` 为默认开启的 checkbox。正式入口必须在音乐 session 的 `finally` 清理以及关闭失败的状态映射之后调用上述路径。C2 仅交付决策、偏好及策略读取；renderer 和正式入口连接等待 C1 的实际调用结论。

## Reduce Motion

独立 `native/ReduceMotion.swift` 读取 AppKit 的 [`NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`](https://developer.apple.com/documentation/appkit/nsworkspace/accessibilitydisplayshouldreducemotion)，输出一行 `true` 或 `false` 后退出。没有窗口、音乐接口、权限请求或系统设置写入，不给音乐 controller 增加生命周期。

`src/reduce-motion.ts` 只执行随包 `likeit-reduce-motion`，无 shell；1 秒超时用 SIGKILL 终止，输出上限 64 字节。只有零错误退出且 stdout 精确匹配 `true\n` / `false\n` 才接受。缺文件、错误、超时及其他输出返回 `undefined`，反馈函数跳过动画。

`scripts/build-native.py` 在开发机编译 arm64 / x86_64 macOS 13 产物、合并 universal、ad-hoc 签名并校验架构与签名。`assets/native/BUILD.json` 增加 helper 源码摘要、构建命令和二进制摘要。最终用户无需编译或下载安装依赖。编译两种架构不代表 Intel 实机验证。

## C1 隔离预览

在仓库执行 `npm run dev` 注册命令后，从 Raycast 运行 **Preview Confetti (Development)**。`src/preview-confetti.ts` 只执行 `open("raycast://confetti")`，不调用收藏入口或伪造成功。协调者独占执行桌面预览；开发者未触发动效。预览命令须在最终生产 manifest 中移除。

URL 打开成功不是视觉、无确认框、焦点、Space、多屏、时长或并发验证；这些必须由协调者在真实 Raycast 中核对。当前尚未接入正式收藏路径，也不声称本轮行为已验收。
