# 社区歌词接口研究

核实日期：2026-10-11。目标是独立的社区歌词模式：AMLL 优先、LRCLIB 兜底，保留旧网易模式，不新增依赖。本文件记录外部事实与方案建议；最终用户行为、限制数值和验收以协调者冻结的契约为准。

## 结论

- AMLL 适合已有可信网易歌曲 ID 的逐词歌词查询。没有歌曲总时长；文本搜索、别名数组和唯一结果均不能证明录音版本一致。
- LRCLIB 适合按曲名、歌手、专辑和时长查找逐行歌词。服务端允许时长相差 ±2 秒，客户端仍须执行本项目 ≤1 秒的规则。
- 两者是社区数据源。成功取回、XML/LRC 可解析与实际音频同步准确是三项不同证据。
- 不从社区返回值生成或升级网易歌曲身份，不将社区歌词匹配结果用于收藏动作。

## AMLL：接口与身份

官方基础地址 `https://api.amll.dev`，以下读取接口不要求鉴权。原生接口成功包装为 `{ status: 200, data: ... }`；错误包装为 `{ status, error, message }`。应同时检查 HTTP 状态与载荷结构。[概览](https://amll.dev/reference/http-api/overview)

| 用途 | 请求 | 关键行为 |
| --- | --- | --- |
| 按网易歌曲 ID | `GET /v1/lyrics/get?ncmMusicId=442867526` | 精确参数名为单数 `ncmMusicId`，不是 `ncmId` 或 `ncmMusicIds` |
| 按歌词记录 | `GET /v1/lyrics/get?id=1864724189982791` | `id` 是由文件名生成的 53 位整数，是歌词记录身份 |
| 按歌词文件 | `GET /v1/lyrics/get?filename=...ttml` | 文件名必须以 `.ttml` 结束 |
| 文本搜索 | `GET /v1/lyrics/search?musicName=...&artistName=...&albumName=...` | 三字段模糊包含且 AND；有具体字段时忽略 `q` |

`get` 优先级为 `id` > `filename` > 平台 ID。多个平台条件取交集，平台查询仅返回最新匹配记录。`format` 目前只接受 `ttml`。返回的 `musicNames`、`artistNames`、`albumNames`、`ncmMusicIds` 均为数组；包含完整 TTML 的字段是 `lyrics`，没有可靠的歌曲 `duration` 字段。[原生接口](https://amll.dev/reference/http-api/native)、[数据模型源码](https://github.com/amll-dev/amll-ttml-api/blob/main/src/core/models.rs)

`search` 返回 `data.items` 和 `data.pagination`，不返回歌词正文。`page` 从 1 开始，`pageSize` 默认为 50、允许 1–100；非法分页值为 400。空结果与越界页返回空数组，不能当作传输失败。歌词记录 `id` 或 `filename` 对应内容固定；平台 ID 和文本搜索结果会随更新变化。[原生接口](https://amll.dev/reference/http-api/native)

建议自动路径仅在当前快照已有可信 `ncmMusicId` 时查询 AMLL，并再次确认响应 `ncmMusicIds` 包含该 ID；不要以文本搜索第一条或“仅一条”代替身份核对。没有可信 ID 时直接进入 LRCLIB 严格匹配。AMLL `body@dur` 与最后一句结束时间均不能代替缺失的录音总时长。

## TTML：必须明确的解析边界

应按 XML 命名空间识别元素和属性，不假设文件永远使用同一前缀。以下命名空间、时间写法与辅助内容来自项目自身规范。[TTML 规范](https://github.com/amll-dev/amll-ttml-db/blob/main/instructions/ttml-specification-en.md)、[格式概览](https://amll.dev/en/guides/lyric/ttml)

| 内容 | URI / 规则 |
| --- | --- |
| TTML 元素 `tt/body/div/p/span` | `http://www.w3.org/ns/ttml` |
| `ttm:role`、`ttm:agent` | `http://www.w3.org/ns/ttml#metadata` |
| `itunes:key`、`itunes:timing` | `http://itunes.apple.com/lyric-ttml-extensions` |
| `amll:meta` | `http://www.example.com/ns/amll` |
| Apple 辅助内容容器 | `http://music.apple.com/lyric-ttml-internal` |
| 行与词时间 | `p` 和 `span` 的 `begin/end`，允许 `HH:MM:SS.fff`、`MM:SS.fff`、秒数字和 `s` 后缀 |
| 行内辅助角色 | `x-translation` 翻译、`x-roman` 音译、`x-bg` 背景人声 |

规范还允许 `<head><metadata><iTunesMetadata>` 内的翻译/音译，以 `<text for="L1">` 关联 `itunes:key="L1"`。它与行内翻译并存时可能重复。辅助文本不能混入主歌词、不能按其出现顺序误算主词时间。

逐行 TTML 也合法；不能仅因来源是 AMLL 就宣称逐词。词间空格可能是独立文本节点，不能直接 trim 每个词后拼接。背景人声与不同演唱者可重叠。空白 span 可有相等开始/结束时间，不能把这种合法空格误判成整份损坏。`body@dur` 可缺省、仅供参考。[TTML 规范](https://github.com/amll-dev/amll-ttml-db/blob/main/instructions/ttml-specification-en.md)

实现建议：协调者事先冻结 v1 支持的时间格式、行/词时间验证、翻译选择顺序、背景人声处理和不支持结构的回退行为。使用系统 XML 解析器，关闭外部实体解析；拒绝畸形结构及超限内容。不得凭空均分词时间来制造逐词效果。

## LRCLIB：接口与匹配

基础地址 `https://lrclib.net`，匿名读取当前可用。客户端应发送含应用名、版本和项目链接的 `User-Agent`；不能修改该头时可用 `X-User-Agent` 或 `Lrclib-Client`。官网文档为 SPA，本次读取了其页面发布的脚本文档段落。[官方文档](https://lrclib.net/docs)

| 用途 | 请求 / 响应 |
| --- | --- |
| 按元数据 | `GET /api/get?track_name=...&artist_name=...&album_name=...&duration=260` |
| 按记录 | `GET /api/get/791046`，此 ID 不是网易歌曲 ID |
| 搜索 | `GET /api/search?track_name=...&artist_name=...&album_name=...` 或 `q=...`；返回裸数组，最多 20 条，无分页 |
| 记录 | `id`, `trackName`, `artistName`, `albumName`, `duration`, `instrumental`, `plainLyrics`, `syncedLyrics`，以及新字段 `hasWordSync`, `lyricsfile` |

`get` 的 `track_name`、`artist_name` 必填；专辑、时长在 API 层为可选。当前源码限制传入时长为 1–3600 秒，部分响应元数据与歌词可为 null。查询以时长上下各 2 秒筛选并取一个结果，故 200 响应仍须复核本项目全部匹配条件。[get 源码](https://github.com/tranxuanthang/lrclib/blob/main/server/src/routes/get_lyrics_by_metadata.rs)、[匹配源码](https://github.com/tranxuanthang/lrclib/blob/main/server/src/repositories/track_repository.rs)

项目建议：只有当前曲名、歌手、专辑和有效时长齐备才自动查询；对返回字段做既定标准化后精确比较，并验证 `abs(returnedDuration-currentDuration) <= 1` 秒。不得移除 Live、Remix、Instrumental 等版本标记来提高命中率；不接受缺失时长，不退化为第一条模糊搜索结果。API 自身的可选字段不是项目放宽匹配的授权。

`instrumental=true` 表示纯音乐；纯文本与同步字段可为 null。`plainLyrics` 是无时间文本，`syncedLyrics` 是逐行 LRC。新 `lyricsfile` 为 YAML，可含逐词时间，`hasWordSync` 标识这种能力。因此不能声称 LRCLIB 全部只有逐行歌词；本项目无新依赖的 v1 可以明确只消费 plain/LRC，并忽略额外字段。[官方文档](https://lrclib.net/docs)、[Lyricsfile](https://lrclib.net/lyricsfile)

已匹配的纯音乐应显示专门状态；只有纯文本时静态显示并标为未同步。空正文不能冒充纯音乐。LRC 损坏时可以采用有效 plain 文本；不得制造时间轴或将解析失败标为同步成功。

## 错误、资源边界和缓存

| 条件 | 外部事实 | 客户端建议 |
| --- | --- | --- |
| AMLL 400/404/429/5xx | 官方列出参数、未找到、限流、服务故障等错误；单 IP 平均 50 请求/秒 | 404 进入兜底；参数错误不无限重试；限流与故障保持可诊断 |
| LRCLIB 404/400/500/503 | JSON 错误常含 `name/message/statusCode`；503 可为过载 | 不依赖正文必为 JSON，不将故障描述成“确定无歌词” |
| LRCLIB 429 | 官网要求遵守 `Retry-After`，限流正文可能是 HTML；建议串行请求 | 记录源级冷却，切歌也不能绕过；停止当前等待时不继续请求该源 |
| 超时、大小 | 已查文档没有可作为客户端保障的响应时限或歌词字节上限 | 在冻结契约中规定总预算、每源预算、响应字节、行/词数量与 XML 深度上限 |

来源：[AMLL 概览](https://amll.dev/reference/http-api/overview)、[LRCLIB 文档](https://lrclib.net/docs)、[LRCLIB 错误源码](https://github.com/tranxuanthang/lrclib/blob/main/server/src/errors.rs)。

建议单次解析只持有有界数据；切歌、模式切换和关闭窗口使旧请求失效。网络完成后必须核对请求代次与当前歌曲身份，旧结果不得覆盖新歌。失败/取消不是成功缓存；缓存键必须包含模式、来源、匹配用身份/完整元数据及版本。AMLL 按固定歌词记录的缓存可较长，平台 ID 查询的缓存应较短；具体 TTL、条目数和持久化策略由协调者冻结。

## 许可与内容来源

- AMLL API 服务软件：MIT 或 Apache-2.0 双许可。[服务 README](https://github.com/amll-dev/amll-ttml-api#readme)
- LRCLIB 服务软件：MIT。[LICENSE](https://github.com/tranxuanthang/lrclib/blob/main/LICENSE)
- AMLL DB 当前 README 明确区分：外来数据按原提供方协议；提交者自主编写部分按 CC0 1.0。不能把整个库中全部歌词概括为统一 CC0。[共享协议](https://github.com/amll-dev/amll-ttml-db#共享协议)

项目文档应分别记录软件许可与数据来源；这些软件许可不等于对库内所有商业歌词取得统一授权。不将真实商业歌词正文复制为仓库验收 fixture；使用自行编写的短文本覆盖解析行为。

## 本次真实接口取证

仅在内存读取并统计；未保存歌词全文、未操作音乐 app。

| 请求 | 2026-10-11 结果 | 能证明的范围 |
| --- | --- | --- |
| [AMLL 按 ncmMusicId](https://api.amll.dev/v1/lyrics/get?ncmMusicId=442867526) | HTTP 200；id `1864724189982791`；59 个 `p`、524 个带 begin/end 的 span；有 `x-translation`、`x-bg`；无 duration | 平台 ID 参数有效，TTML 可解析；不能证明播放同步精度 |
| [LRCLIB 完整元数据](https://lrclib.net/api/get?track_name=Die+For+You&artist_name=The+Weeknd&album_name=Starboy&duration=260) | HTTP 200；id `791046`；260 秒；plain+synced 均非空；instrumental=false；hasWordSync=false | 该版本有纯文本与逐行 LRC；不能证明客户端时钟或逐词显示正确 |

AMLL 上述记录的曲名别名同时包含 `Die For You` 与带 Instrumental 的名称，进一步说明 alias 数组不是版本准确性的证明。不得把本次命中结果硬编码为产品逻辑。单曲 API 探测不覆盖中文命中率、弱网、长歌词或真实 UI 同步，需在验收中分别记录。
