# 收藏成功彩带：组件与桌面能力研究

研究日期：2026-10-11。目标是收藏确认成功后，屏幕左右两侧向中央喷彩带，同时保持原工作界面。仅做官方文档与固定版本源码研究；未触发动效、未操作音乐应用、未编译或运行候选组件。

## 结论

优先验证 Raycast 内置 `raycast://confetti` 的扩展内调用。Raycast 官方在 v1.35.0 更新日志明确发布了这个 URL；因此“`@raycast/api` 无 confetti 导出”不能推导为“Raycast 不支持桌面彩带”。协调者已提供本机视觉符合左右向中央的观察，但外部 URL 触发出现确认框，扩展内是否仍需确认尚未验证。只有实际调用满足用户流程时才采用内置方案。[Raycast v1.35.0](https://www.raycast.com/changelog/1-35-0)

若内置调用流程或视觉不满足，原生备选为 **ConfettiSwiftUI 3.0.0 + AppKit 非激活透明 NSPanel**。它提供现成粒子形状、方向与数量控制；窗口、显示器选择、Space 策略、减少动态效果和到时清理仍由 Likeit 的小包装承担。canvas-confetti 的双炮台示例最贴近视觉目标，但不能直接在 Raycast 的 no-view JavaScript 环境绘制桌面；需再加原生窗口和 WebKit 容器，集成成本更高。

## Raycast 的现成能力与边界

- **官方可触发入口**：`raycast://confetti`。更新日志原文为 “Use the new `raycast://confetti` URL scheme to trigger confetti.”，发布于 2022-05-18。扩展可通过 `open("raycast://confetti")` 调用 URL；这是官方 URL 与官方 `open` API 的组合。[更新日志](https://www.raycast.com/changelog/1-35-0)、[open API](https://developers.raycast.com/api-reference/utilities#open)
- **未找到的契约**：已检查官方开发文档、手册及相关更新日志，未找到这个入口对左右方向、粒子数量、时长、多屏、Space、鼠标穿透、焦点、减少动态效果或完成回调的保证。不要将 URL 成功打开当成上述行为通过；也不要依赖未经官方确认的查询参数。
- **no-view**：不向 Raycast 主导航栈推入视图，可以导出异步函数调用 API；不代表提供 HTML Canvas 或桌面渲染面。Raycast 提供自己的 UI 组件；本地 `@raycast/api` 1.104.25 类型声明中未发现 confetti、HTMLCanvas 或 WebView 导出。[Manifest](https://developers.raycast.com/information/manifest#command-properties)、[Lifecycle](https://developers.raycast.com/information/lifecycle)、[API 介绍](https://developers.raycast.com/)
- **反馈仍保留 HUD**：`showHUD` 会关闭 Raycast 主窗口并显示底部短消息。其返回值只保证 HUD 已显示；`open` 的返回值也只保证目标已打开。彩带失败不能改变已经确认的收藏结果。[HUD](https://developers.raycast.com/api-reference/feedback/hud)、[open API](https://developers.raycast.com/api-reference/utilities#open)
- **launchCommand 不是已证明的免确认路径**：官方明确跨扩展调用会展示 permission alert；文档没有明确内置 Confetti 的 manifest 标识或其可调用性，不能猜测参数后宣称可以免确认。该 API 的 Promise 也不代表目标命令执行完毕。[launchCommand](https://developers.raycast.com/api-reference/command#launchcommand)

### 协调者提供的本机观察

以下由主协调者报告，本研究子任务没有亲自触发：在 Raycast 搜索 `raycast://confetti`，选择 Open in Browser 后出现 “Request to run Confetti”，包含 Run Command、Always Run Command、Cancel。协调者只点了一次 Run Command，未改变持久设置；截图捕获到全屏浮层，左右下侧的多色纸片朝内上方喷射，视觉符合双侧方向。

此证据仅覆盖该外部打开路径与视觉。**首个实现闭环应由协调者验证真实 no-view 扩展中的 `open("raycast://confetti")`**：是否仍有确认框，HUD 调用前后怎样影响焦点与 Space，以及失败时是否保留准确的收藏成功反馈。不要用跳过确认参数或设置 Always Run 来掩盖集成行为。若确认步骤必现且不符合产品流程，再选原生 fallback。

## 固定候选与能力比较

版本固定到 GitHub tag 对应的完整 commit；不要依赖浮动的 master/main。

| 候选 | 固定版本／许可 | 双侧方向、数量、短时 | 桌面行为与成本 |
| --- | --- | --- | --- |
| Raycast 内置 Confetti | Raycast 自带能力；不是需引入的开源库 | 协调者观察双侧朝内上方；时长待测，没有已确认的参数契约 | 最低代码成本，一个 URL；外部路径有确认框，扩展内确认、焦点、Space、多屏及减少动态效果待测 |
| canvas-confetti | `1.9.4`，`5f77cdeb0b9f6b69558e8369c63071fc9415f842`；ISC | 官方 School Pride 就是左右炮台；可控制 `particleCount`、`angle`、`spread`、`origin`、`ticks`；需把示例 15 秒持续发射缩短 | 浏览器 Canvas 库；需原生 overlay + WebKit 承载。库支持减少动态效果，默认关闭 |
| ConfettiSwiftUI | `3.0.0`，`9ae5bc2ce2149980884d4612321c3a266d6bf82c`；MIT | 两个 cannon 放左右边缘，可分别配置角度、`num`、`radius`、重复次数；没有独立总时长参数 | SwiftUI/macOS 11+；需 NSPanel 包装。源码没有桌面窗口、多屏/Space 或减少动态效果处理 |
| Confetti_Effects | 无 tag；固定 `a95f523f050abe2c31367526929abf331b8b3e02`；MIT | 源码有 origin、角度、数量、速度与 lifespan 参数 | 不推荐：macOS 14+，Package 实际要求 Swift 6.1；README 声称可用的核心类型没有 `public`，需修补或复制源码；同样缺桌面包装 |

### canvas-confetti：视觉参考很合适，不能直接当 Raycast UI

固定版本的 [School Pride 源码，805–830 行](https://github.com/catdad/canvas-confetti/blob/5f77cdeb0b9f6b69558e8369c63071fc9415f842/index.html#L805-L830) 每帧从 `x=0` 以 60°、从 `x=1` 以 120°发射，spread 为 55；两侧均朝屏幕内上方。可改成一次双侧 burst 或很短的发射窗口，而不是照搬 15 秒循环。

库会调用 `document.createElement("canvas")`，需要 Canvas 绘图环境；因此仅在 no-view 命令中 npm import 不能产生桌面 overlay。`disableForReducedMotion` 默认为 false，启用后依据 `prefers-reduced-motion` 跳过动画。[创建 Canvas，316–332 行](https://github.com/catdad/canvas-confetti/blob/5f77cdeb0b9f6b69558e8369c63071fc9415f842/src/confetti.js#L316-L332)、[减少动态效果检查，548–555、611–616 行](https://github.com/catdad/canvas-confetti/blob/5f77cdeb0b9f6b69558e8369c63071fc9415f842/src/confetti.js#L548-L616)

固定 [tag](https://github.com/catdad/canvas-confetti/tree/1.9.4) 与 [ISC LICENSE](https://github.com/catdad/canvas-confetti/blob/5f77cdeb0b9f6b69558e8369c63071fc9415f842/LICENSE)。若复制代码或随包分发库，保留该版权与许可文本。

### ConfettiSwiftUI：可用的原生备选

[Package.swift，1–13 行](https://github.com/simibac/ConfettiSwiftUI/blob/9ae5bc2ce2149980884d4612321c3a266d6bf82c/Package.swift#L1-L13) 声明 Swift tools 5.3、macOS 11。公开的 [confettiCannon 参数，47–79 行](https://github.com/simibac/ConfettiSwiftUI/blob/9ae5bc2ce2149980884d4612321c3a266d6bf82c/Sources/View%2BConfettiCannon.swift#L47-L79) 覆盖角度、数量、大小、颜色、半径和重复间隔；[坐标计算，227–246 行](https://github.com/simibac/ConfettiSwiftUI/blob/9ae5bc2ce2149980884d4612321c3a266d6bf82c/Sources/ConfettiSwiftUI.swift#L227-L246) 支持左右各一个向内炮台。

**短时限制**：爆发与下落时长由 `radius / 1300` 和 `(rainHeight + radius) / 200` 算出，配置类型是 internal。屏幕越宽、发射距离越大，下落越久；不能声称直接提供“任意距离且固定两秒自然结束”。包装可在限定时间淡出并关闭窗口，或对固定源码做有记录的小修改，均属于新增实现。[ConfettiConfig，288–304 行](https://github.com/simibac/ConfettiSwiftUI/blob/9ae5bc2ce2149980884d4612321c3a266d6bf82c/Sources/ConfettiSwiftUI.swift#L288-L304)

固定 [release](https://github.com/simibac/ConfettiSwiftUI/releases/tag/3.0.0) 与 [MIT LICENSE](https://github.com/simibac/ConfettiSwiftUI/blob/9ae5bc2ce2149980884d4612321c3a266d6bf82c/LICENSE)。随包编译进已有 Swift helper，或保留许可 vendoring 源码，最终用户均不需安装 Xcode；这是基于本项目已有双架构预编译分发路径的集成建议，未执行构建验证。

### Confetti_Effects：不作为本轮依赖

[ParticleSystem，13–19、92–96 行](https://github.com/taricsa/Confetti_Effects/blob/a95f523f050abe2c31367526929abf331b8b3e02/Sources/Confetti_Effects/ParticleSystem.swift#L13-L96) 有期望的参数，但类和方法均未声明 `public`；[ConfettiCanvasView，11–12 行](https://github.com/taricsa/Confetti_Effects/blob/a95f523f050abe2c31367526929abf331b8b3e02/Sources/Confetti_Effects/ConfettiCanvasView.swift#L11-L12) 也不是公开类型。README 的 Swift 5.9 和 `from: "1.0.0"` 示例与本次读取到的 [Swift tools 6.1 manifest](https://github.com/taricsa/Confetti_Effects/blob/a95f523f050abe2c31367526929abf331b8b3e02/Package.swift#L1-L20)、[空 tags 列表](https://api.github.com/repos/taricsa/Confetti_Effects/tags) 不一致；不值得为本需求引入这些修补。[MIT LICENSE](https://github.com/taricsa/Confetti_Effects/blob/a95f523f050abe2c31367526929abf331b8b3e02/LICENSE)

## 原生备选的最小包装

以下是由 Apple API 能力组合出的实现建议，**不是任何彩带组件已经保证的行为**：

1. 建立透明、无边框、非激活的 NSPanel，内容为两个 ConfettiSwiftUI cannon；不调用激活 app 或设为 key window 的路径。`nonactivatingPanel` 官方定义为不激活所属 app；`ignoresMouseEvents=true` 提供鼠标穿透。[nonactivatingPanel](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel)、[ignoresMouseEvents](https://developer.apple.com/documentation/appkit/nswindow/ignoresmouseevents)、[isOpaque](https://developer.apple.com/documentation/appkit/nswindow/isopaque)
2. 按确定的产品规则选择显示器并使用该屏幕坐标；需要所有显示器时才为每个屏幕建窗口。`NSScreen.screens` 能枚举显示器，但第一块屏幕不一定是活跃窗口所在屏幕，不能用索引 0 冒充当前工作屏幕。[NSScreen.screens](https://developer.apple.com/documentation/appkit/nsscreen/screens)
3. 可使用 `canJoinAllSpaces` 与 `fullScreenAuxiliary` 的公开能力，让窗口可在 Space／全屏空间显示；它们不替代真实全屏、多屏和 Space 不跳转验证。[canJoinAllSpaces](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallspaces)、[fullScreenAuxiliary](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/fullscreenauxiliary)
4. 发射前读 `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`；为 true 时保留文字成功反馈并跳过彩带。设置改变可用官方通知响应。[Apple 减少动态效果 API](https://developer.apple.com/documentation/appkit/nsworkspace/accessibilitydisplayshouldreducemotion)
5. 一次触发、有限生命周期，到时淡出／关闭窗口并退出；组件错误不回滚收藏，不重试收藏、不改变原成功状态。彩带只由已经确认的首次 `liked` 结果触发，`already-liked`、未知或失败状态不触发。此处为建议，最终触发语义由协调会话确定。

## 需要协调者确认的结果

- Raycast 内置效果已由协调者观察为左右朝内上方；实际持续时间与是否因节日设置改变样式仍待确认。
- 首先验证真实 no-view 扩展内的 URL 是否仍弹确认；再确认收藏成功路径是否保持前台 app、键盘焦点和 Space，以及先后调用 HUD 与 URL 的实际结果。
- 当前显示器／多显示器与另一个 app 全屏时的行为；减少动态效果开启后的行为。
- 若选原生 fallback，确认显示器策略、时长以及是否接受到时淡出。构建、双架构和真实桌面行为尚未验证。

本研究只创建此文件，未改产品代码、计划、验收资料或测试，未提交。
