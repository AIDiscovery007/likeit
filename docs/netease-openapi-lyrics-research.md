# 网易云 OpenAPI 歌词接入证据

调查日期：2026-10-11。范围仅为官方公开资料；未安装或运行 CLI，未读取本机账号、Keychain、Cookie、音乐应用缓存或 UI，未使用文档样例凭据。用户已向协调会话确认拥有自己的 OpenAPI 应用及歌词接口权限；这解除申请资格的待确认项，不等于已验证具体请求。

## 当前结论

后续经授权的离线分析已从官方发行包确认 RSA 签名、请求编码及动态命令清单解析方式，可以据此开发有界、默认拒绝未知状态的 provider。凭据稍后提供，因此尚未验证真实鉴权、权限和当前歌曲映射。逐字高亮并非接入普通歌词的必要条件；若实测合法响应含可解析的 `data.lrc`，可先复用现有 LRC 展示，不推测逐字时间字段。

## 已有官方证据

| 问题 | 可据以决策的证据 |
| --- | --- |
| 应用凭据 | 网易官方 `NetEase/skills` 指向 `@music163/ncm-cli`，要求先入驻并申请 `appId` 和 `privateKey`。仓库提供个人开发者申请入口；不能沿用样例应用、签名或 token。[官方仓库 README](https://github.com/NetEase/skills#readme)、[官方安装说明](https://raw.githubusercontent.com/NetEase/skills/master/ncm-cli-setup/SKILL.md) |
| 本地使用与登录 | 官方安装说明要求 CLI 配置上述两项并完成用户登录。官方 npm 包 README 提供 `configure` 向导和使用网易云 App 扫码登录的流程，因此“所有客户端都必须配一个后端”没有依据。说明未承诺其配置文件加密、Keychain 保存或避免命令历史泄露。[官方安装说明](https://raw.githubusercontent.com/NetEase/skills/master/ncm-cli-setup/SKILL.md)、[官方发行包 0.1.7](https://registry.npmjs.org/@music163/ncm-cli/-/ncm-cli-0.1.7.tgz) 内 `package/README.md` |
| API 歌曲 ID | 官方操作说明第 74 行明确区分用于 API 的 **32 位 hex 加密 ID** 和用于唤起客户端的 **数字原始 ID**，并说明搜索结果同时含两种 ID。它没有规定 hex 必须大写，也未说明加密 ID 是否跨应用稳定。[官方操作说明](https://raw.githubusercontent.com/NetEase/skills/master/netease-music-cli/SKILL.md) |
| 有授权的映射路径 | 官方说明给出 `ncm-cli search song --keyword …`，搜索结果含两个 ID；具体参数须通过命令树/帮助确认。这支持“官方搜索返回 ID 对”的路线，不能证明存在任意数字 ID 直接转换接口。[官方操作说明](https://raw.githubusercontent.com/NetEase/skills/master/netease-music-cli/SKILL.md) |
| CLI 与歌词 | npm 包 README 宣称 TUI 支持歌词同步，并列出 `ncm-cli tui` 与 `L` 歌词视图快捷键。已读官方说明没有列出独立歌词读取命令，也没有明确承诺支持本次逐字歌词 endpoint。[官方发行包 0.1.7](https://registry.npmjs.org/@music163/ncm-cli/-/ncm-cli-0.1.7.tgz) 内 `package/README.md` |
| token 刷新 | 0.1.7 的官方发行包 README 记载 token 过期自动刷新、`login --check` 主动续期。它未公开 token 的 audience、具体有效期、匿名 token 适用接口或刷新参数。[官方发行包 0.1.7](https://registry.npmjs.org/@music163/ncm-cli/-/ncm-cli-0.1.7.tgz) 内 `package/README.md` |

实现推论：若当前歌曲有可信数字原始 ID，可以用授权搜索返回的原始 ID **完全相等**验证对应的加密 ID，再请求歌词；只匹配歌名、歌手或时长不能证明同一录音。MediaRemote UUID 没有在上述官方 ID 规则中出现，不能改格式后当 `songId`。以上是基于官方 ID 定义的实现约束，不是官方提供的转换算法。

## 用户提供的逐字歌词接口材料

来源指向[逐字歌词官方文档](https://developer.music.163.com/st/developer/document?docId=0f7801d7d6d24180b8fc9058d1ffe593)，endpoint 为 `https://openapi.music.163.com/openapi/music/basic/song/lyric/word/by/word/get`。本次未能独立读取该页正文，下列内容仅记录用户所给材料，不提升为已经核实的完整协议：

- 公共参数包括 `appId`、`signType=RSA_SHA256`、`timestamp`、JSON `device`、`accessToken`、`sign`；`bizContent` 包含加密 `songId`。
- 成功 `data` 包括 `lyrics[{start,duration,words[{suspend,duration,words}]}]`、`ytlrcs`、`lrc`、`tlyric`。
- 用户所给说明称 `code=200, data=null` 表示没有逐字歌词。它不能说明同一首歌也没有普通歌词。
- 协调会话另外报告：对该 endpoint 不带参数、Cookie、凭据的 GET 返回 HTTP 200，但业务 `code=400`、消息为“请求参数不得为空”。这仅证明 endpoint 可到达，未验证鉴权、ID、歌词权限或成功数据。

## 仍未知及后续最小验证

| 未知 | 需要的证据；当前处理 |
| --- | --- |
| 精确签名 | 下方离线补充已确认规范；时间有效窗口与签名成功的真实响应仍未知。 |
| device/token | 已确认官方客户端发送字段和传输层可省略 token；服务器各字段必填性、允许值及歌词能否使用匿名 token 仍未知。采用用户明确提供的 device，不复制 CLI 或样例设备身份。 |
| 歌曲映射 | 官方客户端支持从动态清单发现搜索命令及读取双 ID；需要用户应用真实响应验证。未证实直接 ID 转换或 MediaRemote UUID 映射。 |
| 普通歌词 fallback | 已确认官方 `song lyric` 命令及其响应读取方式；HTTP path/method 由授权清单决定，不能猜固定 endpoint。 |
| 时间和翻译 | `start`/`duration`/`suspend` 的单位、`suspend` 是否相对行首或前一字、`ytlrcs` 与原词对齐规则均未核实。不要猜算逐字动画；普通 LRC 可独立验证。 |
| 无歌词与错误 | `data=null`、空 `lrc`、无权限、token 失效、签名错误、限流、网络错误需分别验证。不能将 HTTP 200 视为业务成功，也不能把鉴权失败显示为“无歌词”。 |
| 分发 | 官方自有应用本地 CLI 是可行形态的证据；未发现可据以宣称“将一份共享应用私钥打包进 Raycast 扩展”的官方许可。个人本地密钥与公开共享密钥是不同部署决策；若要集中保管共享密钥，可评估后端签名，但这是架构建议，不是已核实的网易强制要求。 |

## 检索限制与材料定位

`web` 直接打开文档站失败；初始公开 HTML 可获取但没有文档正文，页面依赖的 CDN 脚本连接失败。随后浏览器工具明确报告文档站被 site-safety policy 阻止，已停止该路径，未通过其他浏览器、代理或执行手段绕过。上述官方 GitHub 仓库与 npm 发行包是独立的替代来源。

官方仓库链接的 npm 最新版为 0.1.7；[版本元数据](https://registry.npmjs.org/@music163/ncm-cli/0.1.7) 对应 tarball 的 SHA-512 integrity 在本地核对一致。发行包只有两个 JS 文件、`package.json` 和 README；JS 经 `javascript-obfuscator` 混淆。最初只读 README，后续按协调会话明确授权开展下方限定离线分析；没有运行完整 CLI 或加入项目依赖，已读官方资料也未链接独立的未混淆签名 SDK。

## 离线补充：可实现的签名与请求

来源为[官方 0.1.7 发行包](https://registry.npmjs.org/@music163/ncm-cli/-/ncm-cli-0.1.7.tgz) 的 `package/dist/index.js`。下列括号内数字为该原始 UTF-8 文件的零基字节范围 `[start,end)`，便于在不可读的发行文件中精确复查。包 integrity：`sha512-2J1FKl8BxdNDjC9aAJ8WiTypWsfhyKUcS7UErYbNDNOhqD7eXCyGSOfUeMZYWhHy+CcxNllNFDhdFLqq5zS3tw==`。

只将已检查的纯字符串表 `E`、解码器 `k` 和初始字符串表旋转片段放进隔离 `vm`，禁用动态代码生成、设置超时，不提供 `require`、`process`、文件或网络能力。其余代码仅通过 AST 常量解释和文本替换查看，未执行初始化、请求、配置读取、设备探测或业务函数。检查副本位于 `/tmp/likeit-official-readable.js`；定向摘录位于 `/tmp/likeit-official-protocol-excerpts.js`，两者都不是产品代码。

- **待签名文本**：`qu`（263516–264146）枚举请求对象，排除键 `sign` 以及值为 `null`、`undefined`、空字符串的项；其余值使用 `String(value)`，键以 `localeCompare` 排序，每项组成 `key=value`，以 `&` 连接。此时不做 URL 编码，URL、HTTP 方法也不进入该签名函数。
- **RSA**：`Hu`（266479–268065）用 Node `crypto.createPrivateKey` 读取 PEM/PKCS#8，以 `createSign('SHA256')` 更新待签名字符串，结束后 `sign(key, 'base64')`。它没有设置其他 padding，主会话可用 Node 默认 RSA 签名行为做生成密钥的离线向量验证；不是从算法名称猜实现。
- **密钥输入**：`Yr`（264146–266479）还原文本中的转义换行并 trim；PKCS#1 PEM 转为 PKCS#8，普通 PEM 保留，纯 Base64 DER 文本加 PKCS#8 PEM 包装。`Hu` 也支持密钥文件路径。此行为仅说明官方客户端接受什么，不要求 Likeit复刻所有输入形式。
- **公共字段**：`$.get`（331998–334581）与 `$.post`（334581–337174）构建 `appId`、`signType`、`timestamp=String(Date.now())`、`device=JSON.stringify(deviceObject)`、`bizContent=JSON.stringify(bizObject)`；token 为 truthy 时才加 `accessToken`。随后签名并加 `sign`。JSON 内容不再按键排序，必须签实际发送的字符串。
- **传输**：GET 对完整对象做 `URLSearchParams(...).toString()`；POST 使用 JSON 字符串 body 与 `Content-Type: application/json`。官方客户端发送 `User-Agent: ncm-0.1.7`、`Referer: https://music.163.com/`。这证明传输实现，不证明任意 endpoint 同时接受两种方法；本次逐字接口的 GET/POST 支持来自用户提供材料，仍待真实调用验证。
- **token 边界**：传输层允许不附 token，不等于歌词权限允许匿名访问。官方 `U.getAccessToken`（357519–360839）优先用户 token，必要时尝试刷新，再回落匿名登录；`Zn.login`（342878–344872）调用 `/openapi/music/basic/oauth2/login/anonymous`，`Xn.refresh`（345911–346915）调用 `/openapi/music/basic/user/oauth2/token/refresh/v2`。本次产品可以只接收用户明确提供的 token 并对失效有界失败；不需要实现登录或读取 CLI 缓存。

### 设备对象：观察到的默认值，不是字段必填规范

`$.getDeviceConfig`（331539–331998）生成 `deviceType='openapi'`，`os/channel/brand='ncmcli'`，`appVer='0.1.7'`，`model=平台名+'_'+架构+'_'+source`，`osVer` 取平台版本；默认 `source='cli'`。GET/POST 另加 `clientIp` 和持久 `deviceId`。`Bt.generateDeviceId`（243704–244609）把本机属性哈希为带 `ncmcli_` 前缀的标识，调用方会保存复用。这里没有执行任何设备属性读取。Likeit 应接收用户提供的设备对象；无需仿冒 CLI 的产品身份，也不应因此引入额外公网 IP 探测服务。[来源：官方包](https://registry.npmjs.org/@music163/ncm-cli/-/ncm-cli-0.1.7.tgz)

## 离线补充：动态发现搜索与普通歌词

发行包中的实际 `Js.search` 和 `Js.getLyrics` 通过命令描述执行，并没有在这两个调用点固定 HTTP path。**可以实现仅处理两个命令的有限解析器，无需引入或执行整个 CLI。** 这是基于下列源码的实现判断；尚未拿到用户应用的真实清单。[来源：官方包](https://registry.npmjs.org/@music163/ncm-cli/-/ncm-cli-0.1.7.tgz)

1. `Ki.syncManifests`（585494–587113）在用户已登录时发起已签名 POST `/openapi/v1/ncm/cli/manifest`，业务字段为 `cliVersion` 和 `cachedVersion`；后者是已缓存版本映射的 JSON 字符串。无缓存时该映射为空，客户端版本为 `0.1.7`。响应读取顶层 `manifests` 与 `notices`，**不是** `data.manifests`。
2. `manifests` 是路径键到资源对象的映射。解析两个目标时，先在 `manifests.root.sub_resources` 中以 `name` 找到 `search` 或 `song`，再以该条目的 `path` 取 `manifests[path]`，最后在该资源的 `methods` 中以 `name` 找 `song` 或 `lyric`。缺失任一对象即失败，不猜 endpoint。源码 `Is.resolve`（746636–748378）支持更深层路径，本项目不需要。
3. 方法描述使用 `path`、`http_method`、`parameters`、`fixed_params`、`auth_required`、`auth_provider`。参数可为数组，或名称到描述的对象；后者转成 `{name,...description}`。位置取 `in || location`。`vs.collectParams`（729970–733680）只把已提供的声明参数放入 query/body，取值为 `providedValue ?? default`；固定参数最后覆盖 body。`vs.execute`（724448–725460）对 GET 以 query 作为 `bizContent`，POST 以 query/body 合并结果作为 `bizContent`。CLI 对 body 的数组字符串有 JSON/逗号转换，本项目输入的关键词、limit、songId 不需要此转换。
4. `vs.resolveAuth`（727546–729970）对 `auth_required=false` 返回空 token；为真时使用指定 provider，默认 `netease`，且要求用户登录。对于仅支持用户提供 token 的 Likeit，清单获取及需要认证的命令均应要求已有 token，不自动读取缓存或开始登录。
5. 为把解析限制在本任务内，可以只允许 GET/POST、固定网易 API host、无路径占位符、普通标量 query/body 参数，并拒绝上传预处理参数。此处是本项目的缩小实现范围建议，不是官方 manifest 的完整规范。响应给出的 URL/参数仍需校验，不能让远端描述改变请求目的地或执行代码。

`kt.mergeRemote`（579190–579820）只将含 `methods` 或 `sub_resources` 的远端条目当作完整资源；否则保留对应旧缓存。首次取清单应要求目标资源完整，不把仅有版本的条目当作可执行描述。未发现当前两个命令的实际参数清单，因此哪些参数必填、具体分页字段、服务器返回 schema 仍应以拿到的清单和授权响应为准。

### 已确认的命令调用与客户端读取行为

| 命令/接口 | 官方客户端实际行为 | 不能据此承诺的事项 |
| --- | --- | --- |
| `search song` | `Js.search`（1626372–1627127）传 `keyword`、`limit=20`、`trialScene='tui'`；`Js._extractSearchSongs`（1638676–1639142）读取 `data.songs`，否则 `data.list`，否则把 `data` 视为数组或数字键对象。 | 未取得该方法真实清单；不知道固定 HTTP 路径、所有必填字段或完整分页协议。 |
| `song lyric` | `Js.getLyrics`（1623791–1626372）传 `songId`，要求 `code=200` 且有 data，再读取 `data.lyric` 或 `data.lrc.lyric` 的 LRC 字符串。 | 未证明固定 endpoint；未发现此命令调用逐字接口，也不能把它的返回对象套到用户给出的逐字 `data.lrc` 字符串上。 |
| 单曲详情 | `rs.getSongDetail`（406502–409469）GET `/openapi/music/basic/song/detail/get/v2`，传 `songId`、`withUrl=true`、`bitrate`，可加 `effects/level/immerseType/trialScene`。读取 `data.playUrl/songSize/br/level/duration/name/artistName/albumName/coverImgUrl`；duration 除 1000。 | 此调用专用于播放，甚至拒绝没有 playUrl 的结果；不是批量映射接口的证据，也未证明任意数字 ID 可直接传入。 |

`Js._toSong`（1639917–1642248）的兼容读取顺序如下；这是客户端兼容逻辑，不是所有 alias 都必定出现在真实 API 响应的承诺：

- 加密候选：`songId`，否则 `encryptedId`，否则字符串化 `id`。
- 原始候选：字符串化 `originalId`，否则字符串化 `id`。**Likeit 不应照抄后一 fallback**：必须有可信的数字原始 ID，并与当前桌面歌曲数字 ID 完全相等；加密候选独立验证为 32 位 hex。两者不能相互冒充。
- 曲名 `name`；艺人数组 `ar || artists` 的各 `name`；专辑对象 `al || album` 的 `name`。
- 时长 `dt || duration || 0`，大于 1000 时 `floor(value/1000)`。这个启发式不是统一单位契约，不足以单独证明歌曲身份。

搜索实现只消费一页，没有读取 `total`、offset 或页数。`Js._extractPaginationMeta`（1630126–1630533）用于其他列表：有 boolean `hasMore` 则采用，否则用数量是否达到 limit 推测，但 **search 没有调用它**。因此找不到精确原始 ID 时只能反馈没有确认映射，不能宣称搜索了全部结果，也不能用前几个歌名相似结果代替。

下一步可按上述已证实协议开发并由协调会话运行生成密钥的离线测试；之后再以用户明确指定的自有配置验证真实清单、身份映射和歌词响应。仅凭本报告不能声称 API 已接通。本调查只维护本文，未修改产品、测试、冻结文档，也未运行测试。
