# 透明音响主题开发与验收计划

## 目标与已定决策

把用户提供的 `透明歌词音响.html` 适配成 Likeit 原生沉浸桌面的可选主题。经典音响保留且仍是首次启动默认；用户可在桌面内即时切换，退出重开记住选择。参考副本为 `docs/references/transparent-speaker.html`，共享目录原件保持原样。

- 两个主题：`classic`（经典音响）、`glass`（透明音响）。透明主题包含参考中的 `celadon`（青瓷）、`dusk`（落日）、`night`（夜航）、`paper`（纸页）四个场景，默认青瓷；切回经典不丢失透明场景选择。
- 普通 Raycast「打开沉浸模式」沿用上次选择；Action 菜单可直接打开经典或透明音响，显式选择成为新的记忆。不再增加与桌面内选择冲突的 Raycast 主题偏好。
- 原生 `UserDefaults` 是唯一主题偏好来源。缺失或损坏的已存主题回落经典，场景回落青瓷；URL 未传 theme 保留当前/已存选择，非法显式 theme 回落经典。重复相同选择无业务副作用。
- 视觉锚点：16:9 玻璃面板、黑色窄边框、斜向反光、木色底沿、左上/右下透明扬声器及同心环、高光，粗大左对齐歌词。真实文字保留大小写、Unicode 和原始顺序，长歌词自适应，不照搬大写转换。
- 原生 SwiftUI 实现，使用系统字体；不引入 WebView、第三方 UI 库、远程字体或第二个播放器。HTML 的合成音乐、BPM、示例歌词、文件上传、手工歌词编辑和演示播放控件不进入产品。
- 两个主题消费同一个 `DesktopModel`、`DesktopSession` 和 `DesktopAudio`。切换只改变呈现和主题偏好，不控制网易云，不重置歌词、位置或音频采集，不新增联网、采集或权限请求。
- 律动仅使用已取得的真实 low/mid/high 值。无音频、暂停、遮挡、权限失败、动效 off，以及 system + Reduce Motion 时保持静态；无随机或独立时间驱动的假律动。场景背景允许静态渐变/纹理，无需常驻动画时钟。
- 歌词支持逐字、逐行、翻译、纯文本滚动、纯音乐、无歌词与错误提示；进度未知沿用上游诚实状态。浅色背景必须适配逐字高亮，不能使用固定白字导致不可读。
- 退出按钮、Esc、Cmd+Q、返回原 app、音频重试沿用原链路；当前收藏命令、歌词来源/缓存/兜底和音频三态保持。

## 并行工作边界

基线为 `e45ba29fa21d99e1fbeae46a28bf23b5e207362d`。本协调 worktree：`/Users/qiaochao/.codex/worktrees/transparent-speaker-review/likeit`，分支 `codex/transparent-speaker-theme`。开发会话使用另一个 worktree 和自己的 `codex/` 分支。

歌词会话拥有 DesktopSession/Media/Lyrics/CommunityLyrics/OpenAPILyrics、ImmersiveCore、Recovery、歌词测试和 package.json 来源说明；本任务主要拥有 DesktopView.swift、DesktopMain.swift 的主题路由、src/music-desktop.tsx 的主题入口，以及独立使用说明。需要重叠改动先问本协调者。

已知兼容点：旧 `community-lyrics-highlight-regression.test.mjs` 只编译 ImmersiveCore、DesktopCommunityLyricsCore、DesktopView 三份源文件。新增主题必须维持这条旧编译边界，不能修改测试补依赖。DesktopMain 保留基于 window.occlusionState 的可见性；NSApp.isActive 只在退出恢复焦点时使用。重复 URL 的相同歌词来源不得导致 setLyricsSource 清空歌词。

共享主 checkout 和安装包由原协调会话 `01a12983-b00e-7aa1-afb7-5759139197f0` 串行整合。独立构建仅生成本 worktree 产物；不要运行会覆盖 `~/.config/raycast/extensions/likeit` 的未隔离 ray build/develop，不安装、不 push、不发布。合并后必须根据全部源码重建 app 和 DESKTOP-BUILD.json，不能择一份二进制解决冲突。沿用现有签名方式，不创建证书或更改权限。

## 最小闭环与门槛

| 闭环 | 开发交付 | 协调者验收 | 完成条件 |
| --- | --- | --- | --- |
| T0 契约 | 协调者提交本计划、handoff、BDD、测试及冻结清单 | 在基线运行新增验收，保存预期红灯 | baseline SHA 固定，随后派遣开发 |
| T1 选择闭环 | 默认/合法值/回落/持久化，桌面内经典↔透明切换，普通入口沿用记忆与显式 Action 路由 | 冻结的偏好隔离、跨启动、往返保持状态检查；review URL 不重载业务会话 | 最小代码 commit；透明分支可先有可运行基础面板 |
| T2 视觉闭环 | 玻璃装置、四场景、真实歌词/翻译/纯文本、状态与进度、可访问控件 | 真实 SwiftUI 渲染截图：四场景、两种窗口比例、长中英文/emoji/逐字/无歌词 | 所有视觉锚点可辨、歌词可读、无溢出遮挡；独立 commit |
| T3 行为闭环 | 真实音频驱动，静态降级，共享重试/退出链路，主题切换不中断当前歌曲 | 原有音频/歌词测试、重复切换、URL 重入、权限与动效矩阵；UI 锁下实机检查 | 无假数据/重复采集/重新申请权限，原功能回归通过；独立 commit |
| T4 交付闭环 | 独立主题使用说明，原生双架构 build、lint、类型检查；implementation-complete 报告 | 冻结摘要、完整测试、代码 review、集成源码后重建与安装取证 | reviewer 确认通过后通知原协调者合并；有缺陷返回同一开发会话 |

开发者每个闭环完成即本地 commit 并报告 SHA、路径、验证和未验证项。开发者只写产品代码/使用文档，不写、改或运行测试。先提交可 review 代码，再由协调者测试；测试失败修实现。行为/原生接口/依赖不明确时带证据和选项咨询本协调者，等待期间只做无依赖工作。

## 冻结验收入口

在 `native/DesktopView.swift` 暴露可注入偏好域的真实模型入口，保留 `DesktopModel()` 默认调用：

```swift
enum DesktopTheme: String { case classic, glass }
enum DesktopGlassScene: String { case celadon, dusk, night, paper }
// DesktopModel(themeDefaults: UserDefaults = .standard)
// model.theme: DesktopTheme; model.glassScene: DesktopGlassScene
// model.selectTheme(_ rawValue: String?)
// model.selectGlassScene(_ rawValue: String?)
```

偏好键固定为 `desktopTheme` / `desktopGlassScene`。`nil` 表示沿用选择，非法字符串回落默认。选择方法持久化且只修改这两个展示状态；现有歌曲、歌词、逐字属性、音频及状态字段不变。测试注入独立 UserDefaults suite，不接触用户偏好。除了这个小边界，不规定内部算法或视图拆分。

## 测试范围与证据

- `node --test acceptance/transparent-speaker.test.mjs`：真实模型的首次默认、损坏值、合法值、重复/往返选择、场景独立记忆、重新构造与跨进程持久化、现有状态保持。编译真实 Swift 源码，禁止测试替身替换产品模型。
- `node --test --test-concurrency=2 acceptance/*.test.mjs`：合入最新版歌词后完整回归；原有用例和清单保持原样。限定并发避免既有 Swift 编译超时，不改其超时或断言。
- 视觉矩阵：经典基线对照；透明四场景；1280×800 与 1920×1080（必要时加小屏）；长中英文、emoji、翻译、逐字、纯文本、无歌词/未知状态。截图用真实生产 View，合成文本仅是离线可视化输入，不冒充实机歌曲。
- 原生 UI：桌面内两主题往返至少 10 次，同一窗口、同一 session、音频 tap 数量稳定，歌词/时间/状态不中断；关闭重开记忆；显式主题 URL 与普通打开；键盘/AX 可操作，Esc/Cmd+Q/按钮退出。
- 音频矩阵：off、system+Reduce Motion、always；播放/暂停、权限不可用、窗口遮挡、重试。已有状态为零时两主题静态；无需为主题再造音频测试框架。
- 实机由协调者取得独占 UI 时段后执行，不切歌/取消喜欢来凑场景，不修改系统权限。无法验证的项目明确列为未验证；离线截图、build 和 mock 不证明真实采集/歌词成功。

BDD 是需求依据，测试是证据。只因产品实现失败不能改断言、跳过或减少场景。若测试本身与用户意图矛盾，单独记录原断言、证据、正确预期及影响，取得用户决定后独立勘误；新发现缺陷可增加回归而不削弱旧检查。
