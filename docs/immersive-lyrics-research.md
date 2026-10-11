# 沉浸音乐桌面：歌词与时间轴只读研究

2026-10-11。问题范围：当前网易云曲目的身份、真实歌词来源、播放进度与换曲同步。已做定向源码检查、公开接口请求、临时原生只读探针；未控制播放、收藏、窗口、权限或系统设置，未读 Cookie、Keychain、账号文件或私人缓存数据库。报告不保存歌词正文。

## 结论与已确认决策

采用已有 MediaRemote adapter 获取播放会话，使用网易公开搜索与详情做**严格、唯一的元数据匹配**，再按匹配 ID 请求 LRC。桌面标明“歌词按歌曲信息匹配”。这不是来源 ID 的证明；曲名、完整歌手信息、专辑、时长任何一项缺失或不符，搜索不完整或出现歧义，都显示无可确认歌词，不猜、不模糊回退、不添加逐首贴链接流程。协调者已在本轮研究消息中确认此方向。

本机当前歌可以找到唯一严格候选，已知样本的 LRC 可无 Cookie 读取；因此自动歌词主路径可实现。它仍依赖网易未公开承诺稳定性的接口和 Apple 私有框架，不能承诺所有歌曲、版本或系统均可匹配。

## 本机事实

| 项目 | 只读证据 | 含义 |
| --- | --- | --- |
| 当前媒体 | 三次间隔两秒的 `get --no-artwork` 均为网易云 PID 17055，暂停的 `Fallin' Out`／`Keyshia Cole`／`Just Like You`，时长 267.08 秒 | 不是先前授权收藏样本 Popular；未替用户切歌 |
| 会话身份 | `contentItemIdentifier=747C5296-36FB-41DA-A9FB-C7BF090B3A69`；没有 `uniqueIdentifier` | UUID 只能参与当前会话一致性键，不能当网易数字 ID |
| 进度 | `elapsedTime=31.527732426303857`、`playbackRate=0`；三次一致。`--micros` 得到 `elapsedTimeMicros=31527732`、`timestampEpochMicros=1791708240143214` | 暂停进度与更精确时间锚可读；尚未验证真实播放、拖动后的更新延迟 |
| 原始字段 | 临时探针查看未经转换的 13 个 metadata 字段；无歌词、数字 song ID 或内容 URL。仅另有 artwork identifier `d4ac73b587089818` | 排除了“只是现有 adapter 忽略了本次已有歌词字段”；不能推广为所有歌曲永远不发布 |
| AX | `AXIsProcessTrusted=true`、网易云后台、`AXWindows=[]` | 当前没有可读取歌曲链接；历史前台检查也未暴露窗口子控件或文档链接 |

临时探针仅复制、修改 `/var/folders/0d/cgp0j7d54qx310xj_4nx5bz00000gn/T/likeit-lyrics-readonly.bidame0q/adapter`，用 Apple clang 构建 arm64/ad-hoc framework，仅调用 `get`。其中 `probe-result-final.json` 记录字段类型、有限标识与进度，`ax-result.json` 记录 AX 摘要。没有改项目 vendor 或产品二进制。

现有身份筛选与一致性键位于 `native/LikeitController.swift:117–135`；前后 MediaRemote 与菜单复核位于 `:195–207`。当前原生输出只保留 title/key/playing，未向 TypeScript 输出进度。`src/netease.ts:10–15,86` 是持有收藏互斥锁、25 秒寿命的写入会话，**不能直接作为长期歌词订阅器**。

## 公开歌词与自动匹配实测

全部请求用 HTTPS，无 Cookie、Authorization、账号令牌或加密模拟登录；10 秒探针超时，响应上限 256 KiB。下列为接口事实，不等于网易官方开放平台授权或 SLA。

| 请求 | 结果 |
| --- | --- |
| `GET /api/search/get?s=Fallin%27+Out+Keyshia+Cole&type=1&limit=30&offset=0` | HTTP 200/code 200；总数 45，返回 30。POST 表单同参数也成功，但该页不完整，不能据此批准唯一候选 |
| `GET /api/search/get?s=Fallin%27+Out+Keyshia+Cole&type=1&limit=100&offset=0` | HTTP 200/code 200；33,056 字节；`result.songCount=45` 且 `result.songs.length=45`，完整返回；仅 ID 1616018 同时满足四项严格条件 |
| `GET /api/song/detail?ids=%5B1616018%5D` | HTTP 200/code 200；ID、曲名、完整歌手数组、专辑一致，`duration=267080` 毫秒 |
| `GET /api/song/detail?ids=%5B2052348113%5D` | 已知样本 Popular 的 ID、三位歌手、专辑和时长 215466 毫秒正常返回 |
| `GET /api/song/lyric?id=2052348113&lv=-1&kv=-1&tv=-1` | HTTP 200/code 200；8,041 字节；`lrc.lyric` 有 79 个时间标记，首 00:00.000、末 03:31.531；`tlyric.lyric` 有 66 个时间标记；`klyric.lyric` 空 |

请求均直达 [网易搜索接口](https://music.163.com/api/search/get?s=Fallin%27%20Out%20Keyshia%20Cole&type=1&limit=100&offset=0)、[网易详情接口](https://music.163.com/api/song/detail?ids=%5B1616018%5D)、[网易歌词接口](https://music.163.com/api/song/lyric?id=2052348113&lv=-1&kv=-1&tv=-1)。第三方开源 [search.js](https://github.com/neteasecloudmusicapienhanced/api-enhanced/blob/main/module/search.js)、[lyric.js](https://github.com/neteasecloudmusicapienhanced/api-enhanced/blob/main/module/lyric.js) 只作为路径与参数证据，不应引入整个 API 服务或宣称是官方 SDK。新版逐字接口存在，但本轮没有验证，不纳入首版依赖。

## 建议冻结的匹配边界

1. 先确认 bundle/PID 为当前网易云进程，且两份稳定快照的会话键一致；键包含 PID、UUID、title、artist、album、duration。UUID 或任一字段变动立即清空旧歌词、取消旧请求，不能延用旧搜索结果。
2. 仅用当前非空 title 与完整 artist 字符串构造搜索文本；`type=1,limit=100,offset=0`。要求 code 200、有限非负整数 `songCount`、完整歌曲数组、所有 ID 为合法正整数且不重复，返回数等于总数且不超过 100。缺总数、截断、分页未完整、结构异常均不批准候选。
3. title、album 只允许 Unicode NFC 与首尾空白规范化后完全相等，不能删括号、版本、Live、Remaster 或换成模糊匹配。歌手须完整匹配，不能只比首位或包含关系；不得随意按 `/` 拆分名字（例如 AC/DC）。MediaRemote 是扁平字符串，需明确、测试网易多歌手序列化方式；不能可靠证明完整性时降级。
4. 搜索候选还须时长差绝对值 ≤1 秒，缺失、非有限数、单位不明均拒绝。只有一个不同 ID 通过时才请求其详情；零个或多个均不取第一条。详情再次核对 `id/name/artists[].name/album.name/duration`，不可用搜索摘要替代。
5. ID 只能来自上述唯一候选；禁止把 UUID、标题哈希、固定样本 ID、任意 HTTP 返回 ID 直接送入歌词接口。歌词完成后再核对会话 generation/key；晚到的旧歌结果不能进入当前画面。
6. 即使四项一致，仍可能存在元数据完全相同的不同录音、云盘重标记文件，或搜索索引未呈现的重发版本。唯一只指完整搜索响应内唯一，**不是整个网易目录绝对唯一**；显示“歌词按歌曲信息匹配”，不要称“已验证原曲 ID”。

## 时间轴、解析与降级

- 用现有只读 adapter 的 `stream --no-diff --micros --no-artwork` 接收变化；开启时/恢复时补快照，并做低频存活与同源核对。此路径不需要 AX 菜单写入，也不应因收藏权限缺失而阻止只读画面。流回调分别更新 PID、播放布尔、metadata，非原子快照；稳定键与 generation 验证不可省略。
- 采用 `(elapsedTimeMicros + (wallClockEpochMicros - timestampEpochMicros) × playbackRate) / 1e6` 得到秒级时间锚，再以单调时钟推进本地展示；rate=0/暂停即停止推进。拖动或新时间锚直接定位对应歌词行，不能从上一行排队补播。无效或相互矛盾进度时显示歌词而停止同步高亮，不伪造从零播放。
- 使用 `--micros` 避免默认 ISO 时间戳只有秒级精度；不要每渲染帧启动 Perl。上游 `--now` 本身也标注是近似值。换曲、来源变化、进程退出、流损坏/断开均立即停止旧进度并清除旧歌词。
- 首版只做按行 LRC：限制字节/行数、处理多个时间标签与 `[offset:]`、按时间稳定排序、略过普通元信息。空歌词、纯音乐标记、无有效时标、格式损坏分别诚实显示状态；不把长正文的 HTML 当可执行内容，不把 `tlyric` 当原文替代。歌词全屏使用本地文本渲染。
- 网络只发当前曲目信息和候选 ID 到 `music.163.com`，不上传音频；设置请求和响应大小上限、取消与有界重试。每个稳定会话只启动一次查找并缓存成功结果，避免每帧或每个进度事件搜索。退出时结束流、定时器、请求及进程。
- 无网易云、其他来源、缺少必要元数据、无唯一匹配、无歌词、网络失败、进度未知均保留沉浸画面和极简退出，并给短说明。不能用 mock 歌词、假时间、人工链接流程冒充自动主路径。

## API 边界、成本与待验收

Apple 的公开 `MPNowPlayingInfoCenter` 是播放器发布自身信息的接口；[WWDC22](https://developer.apple.com/videos/play/wwdc2022/110338/) 说明播放器须在拖动、速率与播放状态变化时更新进度，并不提供读任意 app 全局歌词的保证。本机 SDK `MediaPlayer.framework/Headers/MPNowPlayingInfoCenter.h:14–15` 也写明其用途为设置 Now Playing 信息。私有读取维护成本继续由固定的现有 adapter 承担。

精确实现依据：`vendor/mediaremote-adapter/src/adapter/now_playing.m:26–52,93–158`（时间推算与微秒），同文件 `:194–195`（两个标识透传）；`vendor/mediaremote-adapter/src/adapter/get.m:39–98`（异步快照边界）；`vendor/mediaremote-adapter/src/adapter/stream.m:258–350`（不同回调与继承旧状态）；`vendor/mediaremote-adapter/bin/mediaremote-adapter.pl:39–60`（流/时间参数）。前台 AX 历史检查见 `docs/identity-research.md:47`。

旧开源方案通过网易私有 history 文件、通知数据库或 hook 取曲目；[其作者列出的路径](https://github.com/Luoyayu/NeteaseCloudMusic-Current-Playing/blob/master/README.md) 不构成官方接口，也不在本轮允许的私人缓存读取范围内。本轮没有访问这些路径；不能为了提升匹配率静默引入。

预计每首新歌 3 次有界请求（search/detail/lyric），无需新增大型歌词依赖；主要成本是严谨解析、会话取消、窗口生命周期及真实时间轴验收。必须由 reviewer 验证：真实播放与暂停、前后拖动、连续换曲与晚回包、同名多版本/同元数据候选、完整多歌手、搜索截断、离线/空歌词、错误时间戳、进程退出与其他播放器抢占。当前只读探针没有覆盖这些动态场景，不得以可获取 LRC 宣称同步验收完成。
