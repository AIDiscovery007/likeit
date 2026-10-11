# 收藏后的可选反馈

`src/result-feedback.ts` 的 `presentResult` 只编排反馈，不导入 Raycast、不执行进程、不读写音乐。先等待原状态 HUD 呈现；仅 `liked` 才判断动画。`system` 读取 Reduce Motion，仅明确 `false` 才调用一次 `celebrate("system")`；`always` 不读取策略，直接调用一次 `celebrate("always")`；`off` 或无效值跳过。旧 boolean 调用保持 true→system、false→off。策略读取与动画的同步异常、Promise 拒绝均在可选反馈边界消化，不重发 HUD、不重试或改变音乐结果。

Raycast 扩展偏好 `motionMode` 为唯一三态 dropdown，默认 `system`，替代旧 `successConfetti` checkbox；未发布本地版不迁移旧 checkbox 值。正式入口在音乐 session 的 `finally` 清理以及关闭失败的状态映射之后调用上述路径，并传递新三态。读取偏好失败时关闭可选动画，仍显示原 HUD。

## Reduce Motion

独立 `native/ReduceMotion.swift` 读取 AppKit 的 [`NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`](https://developer.apple.com/documentation/appkit/nsworkspace/accessibilitydisplayshouldreducemotion)，输出一行 `true` 或 `false` 后退出。没有窗口、音乐接口、权限请求或系统设置写入，不给音乐 controller 增加生命周期。

`src/reduce-motion.ts` 只执行随包 `likeit-reduce-motion`，无 shell；1 秒超时用 SIGKILL 终止，输出上限 64 字节。只有零错误退出且 stdout 精确匹配 `true\n` / `false\n` 才接受。缺文件、错误、超时及其他输出返回 `undefined`，system 模式跳过动画；always 不调用该读取路径。

`scripts/build-native.py` 在开发机编译 arm64 / x86_64 macOS 13 产物、合并 universal、ad-hoc 签名并校验架构与签名。`assets/native/BUILD.json` 增加 helper 源码摘要、构建命令和二进制摘要。最终用户无需编译或下载安装依赖。编译两种架构不代表 Intel 实机验证。

## 原生 renderer

原内置 URL 探针仍出现确认框，已弃用。`native/Confetti.swift` 独立运行获批的 ConfettiSwiftUI 3.0.0，精确文件与摘要见 `vendor/ConfettiSwiftUI/SOURCE.json`。构建仅在临时副本把爆发与下落时长设为 0.45 / 1.6 秒，原始源码保持原样，补丁要求唯一匹配且另记摘要。完整 MIT 许可证随 assets 分发。

helper 以 `.accessory` 策略创建透明非激活 NSPanel，不能成为 key/main window，鼠标穿透；不调用 activate/makeKey。屏幕固定为启动时鼠标所在 NSScreen，无匹配则跳过。左右各 60 个纸片单轮向内上方喷射，无声无触觉。窗口安装、提交显示且 isVisible 后才输出 `started`；这只确认启动，不证明像素或完整动画符合验收。

独立 `confetti.lock` 使用 O_CLOEXEC/O_NOFOLLOW 和非阻塞 flock，锁覆盖整个进程生命周期，固定 inode 不删除；重复请求立即跳过。原生 CLI 只传绝对锁路径时默认 system，也允许第二参数精确 `system` / `always`；坏值或额外参数直接跳过。system 在启动及显示前复查 Reduce Motion，系统通知切为开启则关闭；明确 always 在这三处均忽略系统策略，不修改系统设置。启动起 2.1 秒淡出、2.4 秒关闭退出，全局队列在 2.9 秒硬退出，避免主线程卡住留下窗口；所有进程资源及锁随退出释放。

`src/confetti.ts` 第三参数默认 system，只有 system/always 启动无 shell 子进程，并将模式作为原生第二参数；无效值不启动。最多 1 秒等待关闭 stdout 的 `started\n` / `skipped\n`，总输出上限 64 字节；坏响应、错误或超时发送 SIGKILL，不重试。启动确认后解除 Node 等待，helper 依靠自身期限退出，不要求 Raycast Node 常驻。音乐锁早已在反馈调用前释放。

## 三态隔离预览归档

三态预览保留在固定提交 `8bc28ae20ce70ca01f8925b847ebfe2b5b44a8f9`。reviewer 可归档该提交、安装依赖并运行 `npm run dev`，在 Raycast 选择 **Preview Motion Mode (Development)** 和必填三态 dropdown 参数。预览使用相同 `presentResult` 和 renderer，HUD 专门显示“Likeit 动效预览（不操作音乐）”。选择只影响本次预览，不读写音乐，也不改变扩展偏好或系统设置。system 遵守系统策略，always 可在 Reduce Motion 开启时验证动效，off 只显示预览 HUD。最终生产 manifest 和源码已移除此入口；预览验证后重新注册最终提交，恢复生产命令清单。

## 上轮隔离预览归档

最终生产 manifest 和源码已移除开发预览。需要隔离预览时，reviewer 可归档固定 C3 提交 `c003c37272a15181bd4b482837330f3c5eff628d`，在归档目录安装依赖并执行 `npm run dev`，从 Raycast 运行 **Preview Confetti (Development)**。预览只显示专用 HUD、读取 Reduce Motion 并调用同一原生 renderer；不调用收藏入口或伪造成功，不绕过系统设置。协调者独占执行桌面预览；开发者未触发动效。验收后应重新注册最终提交，恢复仅有 Like Current Track 的生产清单。

焦点、输入穿透、Space、多屏、真实时长和无残留仍待协调者实测，不用编译或 started 响应替代验收。
