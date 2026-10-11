# Likeit 可行性探索

调研日期：2026-10-11。目标：在任意前台应用中唤起 Raycast，输入 `like` 并执行，将正在播放的歌曲加入原音乐应用的“我喜欢的音乐”。本轮仅探索，未执行收藏、取消收藏、播放、切歌或权限申请。

## 结论

**先做仅支持 macOS 网易云音乐的 Raycast 无界面命令，优先通过辅助功能（AX）操作网易云的原生“喜欢歌曲”菜单。** 本机已证实网易云在后台、没有可读取窗口时仍暴露控制菜单，以及区分 `Like` / `Dislike` 所需的本地化字符串；这是目前证据最充分、无需另行登录的路线。后台读取成功不代表后台执行收藏已经成功，真正收藏及状态确认仍需原型验证。[本机证据](#本机证据)

首版明确支持网易云正在播放的歌曲；“识别任何音乐 app，再回到对应 app 收藏”留待逐个适配。现在不能承诺任意播放器、任意窗口状态均可工作，也不能承诺临近换曲时绝不会收藏错歌曲。

## 本机证据

| 检查项 | 已证实 | 证据位置 / 方法 |
| --- | --- | --- |
| 系统与客户端 | macOS 26.6.2 (25G83)；网易云 3.1.13 (3451) | 系统版本命令；`/Applications/NeteaseMusic.app/Contents/Info.plist` 的 `CFBundleShortVersionString`、`CFBundleVersion` |
| 定位应用 | Bundle ID 为 `com.netease.163music` | 同一 plist 的 `CFBundleIdentifier` |
| URL scheme | 注册了 `orpheus`，未取得“喜欢当前歌曲”的官方 scheme 文档 | 同一 plist 的 `CFBundleURLTypes`；有限官方域名检索没有获得可采用的收藏接口证据 |
| AppleScript | 未找到 `.sdef`、`.scriptSuite`、`.scriptTerminology`，plist 未声明 `NSAppleScriptEnabled` / `OSAScriptingDefinition` | 应用包只读检查；`sdef` 因本机仅配置 Command Line Tools 而不可运行。不能据此断言不存在任何 Apple Event 能力 |
| 后台 AX 读取 | 网易云正在运行，`isActive=false`；`AXWindows` 返回空数组；仍能读取 `AXMenuBar > Controls` | 原生 `NSRunningApplication`、`AXUIElementCreateApplication`、`AXUIElementCopyAttributeValue`；未激活窗口 |
| 菜单状态 | 当前存在 `Play` 和 `Dislike`；二者 `AXEnabled=true`，支持动作列表含 `AXPress`、`AXPick` | 对上述菜单项的只读 AX 属性 / 动作查询；没有执行动作 |
| 本地化语义 | `Like` → `喜欢歌曲`；`Dislike` → `取消喜欢`；`Play` → `播放`；`Pause` → `暂停` | `/Applications/NeteaseMusic.app/Contents/Resources/zh-Hans.lproj/Localizable.strings` 对应键 |
| 定位限制 | 上述不同控制菜单项共用 `AXIdentifier=controlItemTriggered:` | 不能仅靠该 identifier 定位；应结合菜单层级、语义标题及 enabled 状态 |
| 权限 | 当前检查进程 `AXIsProcessTrusted()` 为 true，检查未请求授权 | 这不证明 Raycast 或将来的 helper 已获授权；必须在实际执行上下文检查 |
| 当前歌曲身份 | 本次无窗口的 AX 检查没有取得曲名、歌手或歌曲 ID | 不能以进程正在运行、菜单可点击代替“当前正在播放”；歌曲身份读取仍待验证 |

本轮原生 AX 读取结果表明，可以按网易云进程定位其菜单，无需以“当前前台应用”决定收藏目标；后台执行是否有效仍待验证。执行环境的辅助功能信任状态可通过 Apple 的 `AXIsProcessTrusted` 检查。[权限 API](https://developer.apple.com/documentation/applicationservices/1460720-axisprocesstrusted)

## Raycast 侧

现有项目只是起点：`package.json:8–11` 声明双平台，`package.json:22` 使用 `mode: view`；`src/likeit.tsx:1–8` 是 `useAI` 的 jazz 示例。实际功能无需 AI，应改成 macOS 单平台、`mode: no-view` 的 `Like Current Track` 命令，并添加 `like` 等搜索关键词。[Manifest](https://developers.raycast.com/information/manifest)、[Lifecycle](https://developers.raycast.com/information/lifecycle)

用户流程：唤起 Raycast → 输入 `like` → 回车 → 返回原工作界面并显示简短结果。关键词用于搜索，不等于插件自动设置命令别名；用户可给该命令配置 `like` alias，或设置全局热键直接执行。[Alias 与热键](https://manual.raycast.com/command-aliases-and-hotkeys)、[HUD](https://developers.raycast.com/api-reference/feedback/hud)

实现验证可先用 TypeScript 的 `@raycast/utils` 中 `runAppleScript` 调用 `System Events` 做菜单 UI scripting；这与网易云原生提供 AppleScript dictionary 是两回事。本轮成功的是原生 AX 读取，AppleScript 这条后台调用链及其辅助功能 / 自动化权限还未验证。如其不稳定，再评估打包小型原生 AX helper，并计入构建、签名和分发成本；首版不应要求用户安装 Xcode 或运行时编译。[runAppleScript](https://developers.raycast.com/utilities/functions/runapplescript)

## 推荐执行逻辑

1. 只定位已经运行的网易云；未运行则提示，不自动启动或播放。
2. 检查执行进程权限，读取播放状态、喜欢状态和可获得的歌曲身份。`Play` / `Pause` 是候选状态信号，其动态语义需验证。暂停或状态未知时不操作。
3. 将 `Dislike` / `取消喜欢` 解释为已喜欢，直接返回“已在我喜欢的音乐”。只允许执行 `Like` / `喜欢歌曲`，绝不盲发切换快捷键。
4. 执行前再次读取状态和歌曲身份。身份或状态变化则停止，避免把前一首的判断用在后一首上；并发调用应串行或去重。
5. 执行后读取菜单状态，确认已变为取消喜欢；无法确认则提示“结果未确认”，不要自动重复点击。菜单状态只能证明客户端状态，脚本退出成功不能证明云端同步完成。

其中第 3 步的状态映射有本地资源和当前 `Dislike` 菜单支持，但 `Like → Dislike` 的真实状态转换没有测试。菜单动作针对执行瞬间的当前曲目，并不原子绑定某个 song ID；即使能读取歌曲身份，前后复查也只能降低、不能消除换曲竞争。当前尚不能稳定读取身份，需要实测后明确取舍。不能靠歌名搜索另一份曲目代替当前歌曲，尤其涉及翻唱、现场版、同名曲或云盘歌曲。

若其他播放器正在播放而网易云暂停，命令必须提示网易云未播放，不能收藏网易云的残留曲目。首版不是全系统来源识别器；多个播放器同时播放时，未来的来源识别也需要明确消歧规则。

## 其他路线取舍

| 路线 | 评价 |
| --- | --- |
| 原生 AX 菜单 | 优先。可针对后台进程读取，有“喜欢 / 取消喜欢”的语义依据；执行、刷新和焦点保持待验证。 |
| 模拟网易云快捷键 | 当前菜单有快捷键信息，但切换动作无法保证重复调用只添加；还可能依赖焦点或用户设置。不作为默认方案。 |
| 点击窗口内红心 | 可作为后备探索，但目前无可读取窗口；受布局、语言、窗口模式、控件语义影响。暂不使用坐标点击。 |
| 网易云原生 AppleScript / URL scheme | 未发现可证实的喜欢接口。`orpheus` 的存在本身不能证明支持收藏。 |
| 网易云 Web API | 本轮未取得适用于该用途的官方授权与收藏文档，不以第三方逆向接口作为首版依赖；不要读取客户端 Cookie 或登录数据库。 |
| 系统 Now Playing | 可辅助未来识别来源，但不是通用收藏接口；当前未在本机验证。 |

Apple 的 `MPNowPlayingInfoCenter` 用于应用向系统提供自身播放信息，`MPRemoteCommandCenter.likeCommand` 用于应用注册响应处理；不能据此推断插件能读取全系统歌曲或向任意应用发送收藏命令。[Now Playing](https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter)、[likeCommand](https://developer.apple.com/documentation/mediaplayer/mpremotecommandcenter/likecommand)

第三方开源项目 [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) 提供包含 `bundleIdentifier`、`playing`、`title` 等字段的系统媒体会话数据，但其 README 说明 macOS 15.4 后直接调用 MediaRemote 的方案发生变化、需要 helper。可作为二期候选，需要单独验证 macOS 26.6.2 兼容性和私有框架维护成本；它尚未在本机安装或运行。系统媒体会话也不能代表电脑的所有实际声音来源。

## 原型验证矩阵

| 场景 | 验收重点 | 本轮状态 |
| --- | --- | --- |
| 网易云在前台 / 后台 | 取得同一歌曲、同一状态；只添加一次；保持预期焦点 | 后台读取已证实，实际操作未测 |
| 最小化 / 其他 app 全屏 | 不依赖窗口坐标，不意外切换 Space 或前台 app | 未测 |
| 网易云无可读取窗口 | 菜单可读、歌曲身份可得、操作有效 | 菜单可读已证实，其他未测 |
| 未喜欢 / 已喜欢 | 未喜欢则添加，已喜欢则不改变 | 已看到 Dislike，转换未测 |
| 连续快速执行 | 不出现先喜欢后取消；并发去重有效 | 未测 |
| 接近换曲 / 自动切歌 | 不把旧状态用在新曲上；不能确认时不点击 | 未测，身份读取是关键问题 |
| 暂停 / 无当前曲目 / 应用未运行 | 可靠提示，不收藏残留曲目、不启动播放 | 未测；当前只观测到 Play 菜单 |
| 无权限 / 权限撤回 | 清晰提示需要的权限，不误报成功 | 未测；当前检查环境已授权 |
| 离线 / 登录失效 / 不可收藏内容 | 区分客户端状态和云端同步结果，不盲目重试 | 未测 |
| 中英文 / 网易云升级 | 菜单定位及状态识别有效，未知版本失效时可解释 | 已读取中英文资源，切换未测 |

下一步先做小范围原型，验证后台 AX 执行、歌曲身份和状态转换这三个核心假设；通过后再完成 Raycast 反馈和权限引导。只有这组验证通过，才把“无需切回网易云、重复执行不会取消喜欢”作为已验证能力。
