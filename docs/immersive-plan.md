# 沉浸音乐桌面：实施与验收计划

## 范围与决策

在现有 Likeit 上新增可选择的沉浸模式。首版支持 macOS 14.2+ 的网易云音乐，以独立 AppKit + SwiftUI/Canvas 窗口实现透明双音响风格、真实音频律动、同步大字歌词和一次退出。原有 macOS 13+ 收藏与彩带路径保持行为不变。用户已要求“确定了方案后直接开干”，无需再次请求方案批准。

视觉和交互以 `docs/immersive-design.md` 为准。音频和歌词依据分别见 `docs/immersive-audio-research.md`、`docs/immersive-lyrics-research.md`。这次明确新增的音频采集和公开歌词读取，替代原初版仅收藏的范围限制；原有验收文件仍保持原样。

1. Raycast 新增 `music-desktop`（view，标题 Likeit），含“沉浸模式”和“收藏当前歌曲”。保留原 `likeit` no-view 命令；收藏菜单调用它。打开列表没有采集副作用。
2. 独立 `Likeit Desktop.app`，固定 bundle ID `com.likeit.desktop`，随扩展预编译分发 arm64/x86_64，无首次编译/下载。AppKit 管窗口、生命周期和退出，SwiftUI/Canvas 管画面。不用 Electron、浏览器全屏或修改系统壁纸。新构建脚本可以独立存在，避免重建无关收藏二进制。
3. 以当前显示器为边界建立可获得键盘焦点的全屏窗口。Esc、明确退出按钮、Cmd+Q 都立即清理窗口/采集/定时器/网络/子进程；不等待渐隐。单实例，再次启动激活原窗口。不得把正常输入或系统快捷键全局拦截。
4. 使用 Core Audio process tap，仅包含验证为 `com.netease.163music` 的当前播放 PID，`unmuted`，不采麦克风、不采所有 app、不录制、不上传声音。本地仅维护短内存缓冲和幅度/频段统计。使用 `NSAudioCaptureUsageDescription`；macOS 权限由用户授予。拒绝/撤销/无音频/不支持时显示静态桌面及明确说明，不重复弹权限或静默扩大采集范围。
5. 独立 `desktopMotionMode` 三模式 preference（system/always/off，默认 system），不读取收藏的 `motionMode`。system + Reduce Motion、off 不启动音频采集；always 仅覆盖桌面的运动选择，不修改系统。跟随系统运行时变化及时生效。真实低中高频能量驱动音膜/光环；暂停/静音/异常在 500ms 内归静，不以随机数、计时正弦波或示例音频充当真实输入。
6. 复用现有固定版本 MediaRemote adapter 做只读元数据和进度获取，独立于收藏锁/press 路径。不能长期占用 `netease.lock` 或复用有 30s 生命周期的收藏 controller。进程输出有大小、超时和生命周期约束；持续流或有界轮询由开发者选择并说明。只接受已核对的网易 bundle/PID；其他播放器成为源后立即清掉歌词和能量。
7. 歌词走网易 HTTPS 公开接口，无 cookie、登录 token、私有缓存或第三方中转。以曲名、完整艺人集合、专辑、时长（差 ≤1s）规范化后全相等且唯一的候选，取 detail 再核对后加载 LRC。搜索完整性必须可证明（有 total 且 total≤取得结果数，首版最多100）；不完整、缺字段、歧义、失败都显示暂无可用歌词。相同数字 ID 重复记录可去重，不同 ID 即歧义。不要搜索拼音/相似度/feat 删除等宽松回退。旁注“歌词按歌曲信息匹配”，不声称拿到了播放器提供的 song ID。
8. 每个曲目标识使用当前 source bundle+PID+contentItemIdentifier+标题/艺人/专辑/时长。变更立即清歌词、取消上一请求；晚到响应不得覆盖新曲目。同曲一次成功加载/一次失败反馈，不按每次进度刷新重复搜索。内存缓存最多20首，关闭清空；不保存听歌历史/整份歌词日志。每次请求最长5s、响应最大1MiB、总搜索/detail/lyric流程最长15s，退出立即取消。
9. LRC 按真实播放位置选择当前行，支持百分/千分秒、多时间标签、offset、重复时间合并；暂停冻结，拖动前后立即重新定位。当前快照年龄>5s或时间非法不外推；未知状态不能假装正在播放。纯音乐/空歌词/无网络保留可用桌面并解释，不展示假歌词。

## 最小闭环

| 闭环 | 开发交付与提交 | 协调者验收 | 过关边界 |
| --- | --- | --- | --- |
| I0 | 本文、BDD、纯核心契约/测试、原有冻结校验由协调者先提交 | 原有68条绿，新功能明确红 | 派遣前固定 baseline SHA |
| I1 | Raycast 菜单、原生 app 包、静态双音响桌面、独立设置、所有退出与单实例 | build/lint；实际打开/退出、焦点、窗口范围、原收藏入口 | 真窗口可进入和退出，暂缺音频/歌词须明示 |
| I2 | 只读播放快照、严格候选匹配、网易歌词、进度同步及竞态清理 | 冻结核心自动化；联网只读；真实暂停/seek/换曲/离线缺口记录 | 可核对真曲目与歌词，不能以固定歌曲演示替代 |
| I3 | 仅网易进程 process tap、频段统计、真实律动与权限/动效模式 | 合成音频核心测试；授权后真实音乐、静音、暂停、撤权/设备范围 | 无权限可退出且静态可用，真实节奏证据单独记录 |
| I4 | 打包、文档、资源清理、回归修复、最终提交 | 冻结完整性、全量测试、双轴 review、真实完整路径和视觉检查 | implementation-complete 后由协调者另判 accepted/待验收 |

每闭环一个本地 commit 和报告。等待协调者时可继续已确定且无依赖的工作。开发者不新增/修改/删除/运行测试；可 build/lint 与不改变音乐/权限的只读诊断。权限授予、真实播放操作和截图验收由协调者统一执行。无证据的权限/接口/身份问题携带证据咨询，不能猜。

## 纯核心验收接口

`native/ImmersiveCore.swift` 只依赖 Foundation/Accelerate，能与协调者的 Swift 驱动单独编译；生产桌面必须实际调用这些逻辑，不能另写一份通过测试的影子实现。接口仅覆盖风险边界，内部组织和算法由开发者决定。

```swift
struct LyricLine { let time: Double; let text: String }
func parseLRC(_ text: String) -> [LyricLine]
func activeLyricIndex(in lines: [LyricLine], at position: Double) -> Int?
func playbackPosition(elapsed: Double, rate: Double, sampledAt: Double,
                      now: Double, duration: Double) -> Double?
struct TrackMetadata {
  let title: String; let artists: [String]; let album: String; let duration: Double
}
struct SongCandidate { let id: String; let metadata: TrackMetadata }
func matchedSongID(for track: TrackMetadata, candidates: [SongCandidate]) -> String?
struct LyricState {
  init()
  private(set) var trackKey: String? // 初始 nil
  private(set) var lines: [LyricLine] // 初始空
  mutating func beginTrack(_ key: String?)
  @discardableResult mutating func accept(_ lines: [LyricLine], for key: String) -> Bool
}
struct AudioFeatures { let rms: Double; let low: Double; let mid: Double; let high: Double }
func analyzeAudio(samples: [Float], sampleRate: Double) -> AudioFeatures
func desktopMotionEnabled(mode: String, reduceMotion: Bool?) -> Bool
```

规范化限 Unicode canonical composition、大小写、首尾和连续空白；不删除标点、版本注释、艺人或专辑。MediaRemote 的扁平 artist 以单元素数组保存，不盲目拆分 `/`；可将候选完整艺人按返回顺序用精确的 ` / ` 连接后与该字符串全等比较（不得只比首位），除此不猜序列化。`AC/DC` 与 `AC / DC` 不等价；这属于元数据推断，多歌手实机仍需验证。id 仅接受正十进制数字。歌词元数据行忽略；offset 以毫秒加到每个时间，负值钳制为0；同时间不同文本按输入顺序换行合并、完全相同去重；无文本的时间行保留为空（清除前一句）。秒必须<60，时间和位置均有限且非负。position 早于首行时 nil，处于行起点时该行，超过末行保留最后一行。

时钟接收同一单调时间域的 sampledAt/now：elapsed≥0、duration>0、0≤rate≤4、0≤now-sampledAt≤5，否则 nil；结果钳制到[0,duration]。暂停 rate=0。MediaRemote timestamp 到此输入的换算和源核对由集成层单独验收。

音频 rms 是有限输入样本的均方根并钳制[0,1]；空数据、任何非有限样本、非法 sampleRate 均返回全0。low/mid/high 为归一化到[0,1]的频段能量响应，分界20–250Hz、250–2000Hz、2000Hz–min(12000,Nyquist)，使用真实样本计算；不约束FFT实现和具体标度，只检验对应正弦频率占优、幅度关系和静音。平滑/衰减/暂停归零在真实生命周期中验收。

## 证据分层

自动化：原68条不动；新增 Foundation/Accelerate 核心固定用例与 manifest 回归。集成：校验 app 包 usage 字段、签名/双架构、read-only 元数据来源、网络界限、迟到响应、进程过滤、资源清理。真实：Raycast菜单→全屏→歌词/能量→Esc/按钮/Cmd+Q，另测重复打开、焦点不抢回、无权限/Reduce Motion、长句/空歌词、暂停/seek/换曲、另一播放器、显示器/设备变化。无法触达的硬件或 OS 权限场景标未验证。

性能验收在本机记录实际 CPU/内存和显示刷新；目标30fps、稳定10分钟内无持续内存增长。空闲/不可见停止采集且降低刷新；退出2s内不留采集或子进程。短探针不替代长期检查；不用放宽测试来掩盖失败。
