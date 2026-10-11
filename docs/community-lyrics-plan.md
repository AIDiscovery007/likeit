# AMLL / LRCLIB 社区歌词开发计划

## 目标与决策

为现有 SwiftUI 沉浸桌面增加可选的社区歌词：可信网易歌曲 ID → AMLL TTML 逐词/翻译；AMLL 不可用 → LRCLIB 严格元数据匹配 → 同步 LRC、静态纯文本或纯音乐状态。只获取歌词，不下载音乐、不操作播放器、不读取账号凭据。

用户在协调会话 `01a12a4e-2254-7a11-9a08-3eda5509baab` 明确授权独立正式开发 session、high effort、协调者先写 BDD/测试与 review、开发者不写测试且每闭环提交、有疑问向协调者咨询；后续明确取消 PR，只需独立 branch 避免干扰，最终本地合并。新要求覆盖旧 handoff 的共享目录安排，本次不 push、不创建远程仓库。

新增 Raycast 偏好 `desktopLyricsSource`：`netease`（默认，现有网易/官方授权行为）和 `community`（AMLL 优先、LRCLIB 兜底）。用户可切换后重开；运行中的 URL 再打开也必须取消旧来源并重新加载。缺失/非法值按 netease；无静默来源切换。社区模式不读取官方配置或私钥。现有冻结 I13 的网易域名限定继续用于旧模式；本次新增模式只额外允许 `api.amll.dev` 与 `lrclib.net`。现有全部验收原样保留。

## 身份与接口

- 绝不把 MediaRemote contentItemIdentifier、曲名、AMLL 唯一搜索结果猜成网易 ID。当前 snapshot 只有 opaque key，因此先复用/提取已有网易公开 search + detail 严格匹配：完整结果、完整曲名/艺人集合/专辑、时长差 <=1 秒、唯一正整数 ID，detail 再次一致。失败仍可独立尝试 LRCLIB。
- AMLL：`GET https://api.amll.dev/v1/lyrics/get?ncmMusicId=<可信ID>`，核验 envelope status、format=ttml、返回 ncmMusicIds 包含请求 ID；缺字段/错类型/错误状态/错关联均不得接受。不使用模糊 search 推定版本，不拼 raw GitHub 文件地址。平台关联是社区数据而非声音指纹，UI标注来源/匹配方式，不承诺同步绝对准确。
- LRCLIB：`GET https://lrclib.net/api/get?track_name=...&artist_name=...&album_name=...&duration=...`。同时核对返回 trackName、artistName、albumName、duration；Unicode规范化/大小写/空白处理与旧匹配规则一致，保留 Remix/Live 等版本词；时长正有限且差 <=1 秒（严于服务自身2秒）。artistName 仅接受完整规范化艺人字符串，与当前 artists 用 ` / ` 连接一致，不能擅拆逗号、&、feat.。不接受缺字段、布尔数值、同名不同专辑或错误版本。服务 get 只返回一个记录，不使用 search 第一项兜底。
- 优先级：有效 AMLL TTML → LRCLIB syncedLyrics → plainLyrics（明确未同步，静态全文可滚动）→ instrumental=true（纯音乐）；instrumental 不得与非空歌词同时被当成有效成功。两源均失败显示诚实的暂不可用状态，保留歌曲/音频/退出。空白歌词不算成功。

## 数据与同步

原有 LyricLine/LyricState 与 DesktopLyrics 接口不破坏。新边界放 `native/DesktopCommunityLyrics*.swift`，自动被现有 Desktop*.swift 构建收集；无需 WebView、npm/Swift 第三方依赖、AMLL 前端渲染器。

TTML 仅实现 AMLL profile：namespace-aware、p begin/end、span begin/end、纯文本节点、行内x-translation 与中文翻译；word时间使用AMLL文档的绝对媒体时间。时间格式支持 hh:mm:ss.fraction、mm:ss.fraction、秒数字、s、ms；有效区间为有限非负且 end>begin，词必须落于所属行区间；仅空白span可begin=end，保留空格而不生成高亮词。背景人声 x-bg 和音译x-roman不混进主词；合法词重叠不等于倒序，不要求前词end<=后词start。没有词时间而行时间完整时保留逐行显示；任一带时间字段非法/嵌套结构不支持时拒绝该文件，走 LRCLIB，不能制造/平均分配逐词时间。禁止 DTD/entity/外部资源，大小 <=1 MiB，XML深度<=64且行/词总数<=20000；文本作为文本渲染。v1仅显示行内翻译，Apple head/metadata关联翻译暂不实现，README明确范围，主歌词仍可用。

每个主句保留原始词间空格，翻译独立行；显示前后句。有效逐词时间才做逐词高亮，LRC仅逐行，plain仅静态。高亮基于已有 playbackPosition；暂停冻结、前后seek立即定位、无进度/超过5秒快照清除同步高亮，换曲/换源即时清空旧内容。减少动态效果只去掉装饰过渡，时间高亮仍准确，不触碰音频采集策略。

## 网络、缓存、生命周期

复用 LyricRequest 有界网络：HTTPS固定域名/路径、GET、无cookie/authorization/credentials、拒绝重定向、流式1MiB上限、单请求5秒。LRCLIB请求用User-Agent标识Likeit和版本（当前无项目远程URL，不伪造链接）；429不自动重试，记录Retry-After冷却时间，期间同源不发请求，重开也不绕过同一进程冷却。每次完整加载15秒总预算（包含网易解析与fallback），到时停止并诚实反馈。AMLL失败立即尝试LRCLIB，不能超过总预算；无自动无限重试/网络轮询，可通过重开/换源重试。

请求携带独立generation，cancel/stop/换曲/换源后不回调、不更新UI。仅内存缓存最多20份成功文档，键含曲目完整元数据+可信ID+来源策略；同key但metadata变化也不能串词。失败/超时不缓存，stop清空，不落磁盘保存歌词。错误文案不回显远端body、凭据或歌词片段。

## 闭环与审查门槛

| 闭环 | 开发提交 | 协调者验证 |
| --- | --- | --- |
| C0 冻结 | 协调者提交research/计划/BDD/driver/Node测试/sha256，记录初始红灯 | 功能未实现导致红灯，不能跳过；此SHA是实现起点 |
| C1 数据 | TTML/词时间/LRC文档模型和纯函数；保持旧类型兼容 | C01–C05解析/时间/恶意XML/翻译/空白保留 |
| C2 获取 | 网易可信ID解析、AMLL与LRCLIB路由/校验、错误与超时 | C06–C12离线URLProtocol真实生产网络链测试，无公网依赖 |
| C3 生命周期 | 取消、generation、成功缓存、换源隔离 | C13–C16迟到响应/取消/缓存/终止，旧provider回归 |
| C4 用户入口 | preference→URL→DesktopSession→SwiftUI，逐词/双语/LRC/plain/纯音乐状态 | 入口静态契约 + build/lint +人工UI/暂停/seek/换源/退出，不能拿编译当视觉验收 |
| C5 集成 | README/使用说明、吸收音频最终提交、合并后构建产物 | 全部冻结校验+全套原验收+新验收+规范与行为review；音频/UI锁释放后安排实机 |

每闭环本地commit即汇报，可继续确定的下一个闭环；未知行为/接口/依赖先咨询。实现者不写/改/删/运行测试，不修改任何计划/BDD/冻结清单；不改.gitignore隐藏变更。协调者在看到实现前写合成fixture与预期，失败修实现。原测试若确有需求错误，必须单独说明证据并经用户确认，不能用实现现状反推测试正确性；新缺陷可追加不削弱旧断言的回归。

## 固定测试接口

验收只约束以下小边界，内部组织自由：

```swift
struct CommunityLyricWord { let start: Double; let end: Double; let text: String }
struct CommunityLyricLine { let start: Double; let end: Double; let text: String; let translation: String?; let words: [CommunityLyricWord] }
enum CommunityLyricSource: String { case amll, lrclib }
struct CommunityLyricDocument { let source: CommunityLyricSource; let lines: [CommunityLyricLine]; let plainText: String?; let instrumental: Bool }
struct CommunityLyricOutcome { let document: CommunityLyricDocument?; let message: String }
func parseCommunityTTML(_ text: String) -> [CommunityLyricLine]
func communityWordProgress(_ word: CommunityLyricWord, at position: Double) -> Double
// invalid position/word => 0; valid fraction clamped 0...1.
final class CommunityLyrics {
  init(sessionConfiguration: URLSessionConfiguration = .ephemeral)
  func load(key: String, metadata: TrackMetadata, neteaseID: String? = nil, completion: @escaping (CommunityLyricOutcome) -> Void)
  func cancel()
  func stop()
}
```

调用者只有已独立验证的网易ID才能传 neteaseID；nil走上面的网易解析。非法显式ID不发AMLL，仍可LRCLIB。completion在main且每次最多一次；取消后零次。旧函数/类型不变。

自动化入口 `node --test acceptance/community-lyrics.test.mjs`；完整回归 `node --test acceptance/*.test.mjs`。只由协调者运行，使用合成歌词和HTTP拦截，不操作真实音乐。测试接口不是产品调试后门。

## 协作与合并

协调者隔离目录 `/Users/qiaochao/.codex/worktrees/community-lyrics/likeit`，分支 `codex/community-lyrics`，起点0eea051。开发session使用其独立托管worktree，从冻结SHA建立 `codex/community-lyrics-development`。主checkout属于音频任务，禁止直接写入。共享文件DesktopMain.swift/DesktopView.swift/README/打包产物最终由协调者协调；不改DesktopAudio.swift、原收藏代码、vendor、权限、签名策略。

音频协调者 `01a12983-b00e-7aa1-afb7-5759139197f0` 持有实机UI/音乐锁，未明确释放前不得启动安装版、播放/暂停/切歌或覆盖Raycast安装目录。独立worktree内build允许。最终先合并其最终audio SHA，再基于合并源码重新构建app与manifest，绝不直接选一侧二进制。远程PR已取消，只本地合并；不自动删除worktree。

验收记录分 implementation-complete / automated-reviewed / real-device-verified / accepted；真实路径未观察就列未验证。来源可用性/社区关联/播放器进度准确性须区分，不把一次接口HTTP200当用户路径完成。
