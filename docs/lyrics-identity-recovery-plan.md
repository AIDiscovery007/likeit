# 歌词尽力获取与自动兜底

## 用户决策与证据

用户于2026-10-11明确：最关键的是拿到歌词，其他次要，不要所有字段缺一不可。本计划明确替代旧沉浸桌面契约中“没有唯一完整匹配就终止整个歌词获取”的最终产品行为；收藏流程、严格匹配函数及精确provider的原契约不变。旧冻结测试不修改，它们继续验证精确路径；新增验收执行真正由DesktopSession调用的恢复编排，不是测试专属策略。

真实故障：50 Feet / SoMo / 50 Feet / 185.714285秒。网易搜索返回93条、91条可完整解析，唯一完整匹配ID526116053；另有缺专辑信息的无关混剪，使整个搜索因 candidates.count != songs.count 被拒绝。生产provider实际返回0行。固定HTTP响应回放及“原曲+无关混剪”两条最小输入仍可复现；仅保留原曲成功。元数据证据可保存，商业歌词不能写入repo或测试日志。

## 最小可交付行为

1. 当前来源仍须来自真实网易PID/bundle并经两次快照确认；曲名非空即可进入只读歌词获取。歌手、专辑、时长、contentItemIdentifier缺失用未知表示，不捏造ID或进度，不影响收藏的严格身份规则。
2. 完整元数据先尝试现有网易精确provider；精确失败进入真正的恢复路径。恢复不要求搜索全集、不因一条坏记录整组失败。只处理上限100条网易结果及20条LRCLIB结果；最多尝试3个排序后的网易候选。
3. 曲名按Unicode NFC、大小写、空白标准化比较；保留Live/Remix等版本词。已有歌手时优先且至少要求已知歌手信息一致（沿用集合/完整flatten语义，不拆AC/DC）。缺歌手可仅按曲名。专辑匹配、时长接近用于排序，缺失或不同不拒绝。同分按稳定ID排序，可尝试有歌词的下一候选；降级状态显示“候选”、实际来源及匹配到的曲名/歌手，不宣称唯一完整匹配。
4. 网易候选ID来自搜索并经详情核对ID、曲名及已知歌手；不能用MediaRemote UUID当网易ID。详情仅专辑/时长不同不拒绝。严格官方originalID到songID映射、鉴权、私钥与响应解析不放松。
5. 固定顺序网易→AMLL→LRCLIB：网易精确路径后候选网易官方（有合法配置）或公开（无配置），失败自动AMLL，再LRCLIB。官方配置错误/鉴权失败可去社区，但不悄悄绕过官方配置去网易公开。用户进一步确认默认严格按网易→AMLL→LRCLIB串行，任一成功即停止；三个都失败统一显示“暂时没有匹配的歌词”。生产桌面使用这个固定顺序，不需手动切来源。旧source参数保留兼容入口，但不改变本轮固定获取顺序。
6. LRCLIB使用真实 /api/search，track_name必填，artist_name可选，不用album/duration过滤掉歌曲；响应数组按上述规则排序，逐行优先、其次纯文本，纯音乐诚实表达。官方文档 https://lrclib.net/docs；服务端 https://raw.githubusercontent.com/tranxuanthang/lrclib/main/server/src/routes/search_lyrics.rs 。
7. 整个获取最迟20秒结束，精确首阶段最多4秒；单个公共请求最多4秒；给后备来源留下机会，429尊重Retry-After，不重试风暴。取消/换歌/切来源/退出取消所有阶段，迟到结果不能串歌。网络保持现有无cookie、无凭据跨域、无重定向、1MiB响应上限。
8. 成功的恢复结果使用现有LyricDiskCache安全存储和限额，新增版本命名空间和完整输入指纹（允许未知字段）。包含固定串行策略版本、实际结果来源/候选、官方配置身份摘要；不把凭据明文落盘，不与严格结果键混用。读取恢复缓存必须在任何网络匹配之前。缓存已有30天TTL/200条/20MiB/1MiB单条约束保持；失败不缓存，取消不落盘。跨进程重新打开命中并标记本地缓存。缓存损坏重新获取。
9. 已取得歌词不依赖播放进度才可见：无可靠时间显示静态全文，不虚构高亮或进度。同步时间可用时恢复现有逐行/逐词展示。

## 产品接口与验收边界

新增 native/DesktopLyricRecovery.swift（可同前缀拆分），DesktopSession真实调用。构造参数：lyrics: DesktopLyrics、community: CommunityLyrics、sessionConfiguration: URLSessionConfiguration = .ephemeral、configurationURL: URL = OpenAPILyricConfiguration.defaultURL、cacheDirectory: URL? = nil、cacheNow: () -> Date = Date.init。现有CommunityLyrics可以供解析与缓存复用，但它包含AMLL→LRCLIB内部兜底，编排须避免提前或重复调用破坏网易→AMLL→LRCLIB的固定顺序。旧provider不能反向依赖恢复模块（旧固定编译列表保持有效）。

load(key: String, metadata: TrackMetadata, preferredSource: String, completion: (恢复结果)->Void)，cancel()/stop()。结果暴露 lines:[LyricLine]、community:CommunityLyricDocument?、message:String、readableText:String?；readableText由实际歌词生成供生产无时钟静态展示，不由测试生成。DesktopSession保留两provider带cacheDirectory的真实构造并注入恢复编排。

DesktopSnapshot.init(_ data:[String:Any], expectedPID:pid_t? = neteasePID()) 可注入只读PID依赖；生产默认仍查真实网易PID。缺可选字段不拒绝，duration未知用0，elapsed/rate不可伪造。新增验收只替代系统输入与HTTP响应，直接调用生产快照和编排。

## 闭环、分工与合入

I0 协调者先冻结本计划、BDD及自动化，保存真实旧故障和新入口未实现红灯。
I1 原high开发会话实现元数据接纳、候选恢复及源切换，提交本地commit。
I2 同开发会话接入缓存、无时钟全文、取消与使用文档，构建/lint并提交，报告SHA和未验证项；不写改跑测试、不安装、不操作音乐、不改密钥/TCC/签名。
I3 协调者运行原407项及新增验收，独立Spec/Standards review；缺陷修产品，新增回归单独冻结。主协调者合入安装，歌词协调者独占只读UI验证实际歌词可见、跨进程缓存；未实际验证不宣称成功。

歌词协调会话：01a12a4e-2254-7a11-9a08-3eda5509baab。开发会话：01a12ac1-211d-7713-a22e-46e33031b479。保持独立branch/worktree，无PR/push。任何契约歧义携证据向协调者咨询，不自行猜测。
