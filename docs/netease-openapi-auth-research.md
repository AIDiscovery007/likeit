# 网易云 OpenAPI 凭据与登录链路证据

调查日期：2026-10-11。只读官方资料与先前校验过 integrity 的 `@music163/ncm-cli@0.1.7` 检查副本；未执行 CLI、读取用户凭据或账号缓存、访问音乐 UI、提交任何网络认证请求。范围为 token 来源、设备信息、认证 host 与应用类型差异。

## 可据以决策的结论

- 四项应用凭据不能在本地计算出用户 `accessToken`。官方 CLI 先向服务端申请匿名 token，再通过扫码授权获得用户 token；没有找到此应用体系使用 OAuth `client_credentials` 的官方证据。不能据此断言平台完全没有其他授权方式。
- `appId` 同时用于公共 `appId` 和登录业务参数 `clientId`；私钥用于 RSA-SHA256 签名。首次匿名登录和二维码流程不使用 app secret；刷新接口明确使用 `clientSecret`。当前检查到的公共请求构造不发送 RSA 公钥。[官方发行包](https://registry.npmjs.org/@music163/ncm-cli/-/ncm-cli-0.1.7.tgz)
- 官方安装说明要求配置 `appId`/`privateKey` 后完成登录，官方 README 将其指向个人开发者申请入口。[安装说明](https://raw.githubusercontent.com/NetEase/skills/master/ncm-cli-setup/SKILL.md)、[README](https://raw.githubusercontent.com/NetEase/skills/master/README.md)
- 未找到 `b3010` 与 `a3010` 前缀含义的官方定义。不能由前缀推出产品、权限、host 或是否支持 CLI 登录；需查看该应用控制台的应用类型、已开通接口和相应接入说明，提供这些非秘密信息即可。

## 官方 CLI 的精确认证调用

以下为客户端实现证据，不是针对用户应用的成功调用记录。所有路径共用签名请求层；`bizContent` 和 `device` 都先序列化为 JSON 字符串。

| 阶段 | 方法与路径 | `bizContent` | token 与返回值 |
| --- | --- | --- | --- |
| 首次匿名登录 | POST `/openapi/music/basic/oauth2/login/anonymous` | `{"clientId":"<appId>"}` | 不附 `accessToken`；要求 `code=200`，读取 `data.accessToken`，另外读取 `refreshToken`、`expireTime`。 |
| 获取二维码 | GET `/openapi/music/basic/user/oauth2/qrcodekey/get/v2` | `{"type":2,"expiredKey":"300"}` | 官方 provider 先取得可用 token；新设备此时为匿名 token。读取 `data.qrCodeUrl`、`data.uniKey`。 |
| 查询扫码状态 | GET `/openapi/music/basic/oauth2/device/login/qrcode/get` | `{"key":"<uniKey>","clientId":"<appId>"}` | 携带上述 token；`code=200` 后读 `data.status`。`803` 成功时用户 token 是 **`data.accessToken.accessToken`**，同一嵌套对象中有 `refreshToken`、`expireTime`。 |
| 刷新用户 token | GET `/openapi/music/basic/user/oauth2/token/refresh/v2` | `{"clientId":"<appId>","clientSecret":"<appSecret>","refreshToken":"<user refresh token>"}` | CLI 的 `clientSecret` 来源为 `NETEASE_APP_SECRET`，未设置时发空串；这不证明服务器允许空串。读取 `data.accessToken`、`data.refreshToken`、`data.expiresTime`。 |

来源：[官方发行包](https://registry.npmjs.org/@music163/ncm-cli/-/ncm-cli-0.1.7.tgz)。本机精确定位：`/tmp/likeit-official-protocol-excerpts.js:454` 为匿名登录、`:508` 为刷新、`:611` 为 token 选择、`:666` 为匿名 token 保存；`/tmp/likeit-openapi-auth-excerpts.js:11` 为二维码、`:30` 为轮询、`:104` 为 provider 调用顺序。后者只是从先前解码副本抽取并用 Prettier 格式化的文本，没有执行原包代码。

轮询实现每 3 秒查询；`800` 被展示为过期、`801` 等待扫码、`802` 等待 App 内确认、`803` 成功。CLI 获得 token 后还请求用户资料；业务 `301` 时提示检查授权用户是否与 appId 创建者一致。这只是客户端针对该错误的提示，不能提升为所有应用只能创建者登录的通用规则。来源同上，认证摘录第 64、125 行。

## Host 证据与限制

发行包默认环境将 `dr` 设置为 `https://openncm.music.163.com`。随后 `Ia = dr || "http://openapi.music.163.com"`，API 构造函数使用 `baseUrl || Ia`。因此代码保留了 openapi 的备用地址，并允许调用方设置 host；默认运行使用 openncm。

来源：[官方发行包](https://registry.npmjs.org/@music163/ncm-cli/-/ncm-cli-0.1.7.tgz)；`/tmp/likeit-official-readable.js` 中解码 UTF-16 偏移为：环境赋值 `3262`、`sxzoJ` 的 `B || b` 与 openapi fallback 常量 `212805`、`Ia` 赋值 `213810`；构造函数见 `/tmp/likeit-official-protocol-excerpts.js:202`。

这支持“官方客户端保留过同一路径接口层的 openapi fallback”，**不能证明**当前两个 host 对用户应用的签名、token audience、设备字段或权限完全等价。Likeit 当前逐字 endpoint 的 host 来自用户提供文档；不得因 CLI 源码而自动替换。本文不建议使用包内的 HTTP fallback 传输凭据。

## 公共签名与设备来源

匿名认证最小已确认的请求结构为：`appId`、`signType="RSA_SHA256"`、`timestamp=String(Date.now())`、`device=JSON.stringify(deviceObject)`、`bizContent=JSON.stringify({clientId:appId})`、`sign`；首次不附 token。签名前排除 `sign` 和 null/undefined/空字符串值，其余值字符串化，按键名 `localeCompare` 排序，拼接 `key=value` 并以 `&` 连接；私钥 SHA256 签名后 Base64。POST body 为 JSON、`Content-Type: application/json`。不能把 app secret 用作 RSA 私钥或自行添加 `grant_type`。来源与更多签名定位见[已有研究](netease-openapi-lyrics-research.md#离线补充可实现的签名与请求)。

CLI 在本地生成、保存并复用 `deviceId`，没有先调用设备注册接口获取它；它将平台、架构、用户目录等本机属性哈希后加 CLI 前缀。设备对象发送 `deviceType`、`os`、`appVer`、`channel`、`model`、`brand`、`osVer`、`clientIp`、`deviceId`。证据：`/tmp/likeit-official-protocol-excerpts.js:18`、`:218`、`:239`、`:569`；[官方发行包](https://registry.npmjs.org/@music163/ncm-cli/-/ncm-cli-0.1.7.tgz)。

它证明 device 是客户端描述，不是用 app secret 换得的另一份平台凭据。CLI 的 `deviceType="openapi"` 与 `os/channel/brand="ncmcli"` 是实际默认值，不是字段必填性或允许值规范。Likeit 应有自己的稳定设备身份；没有官方依据要求哈希用户目录或增加公网 IP 探测。`ncmcli` 是官方客户端实际使用的协议标识；不能单凭字段名称把它们当作物理系统/硬件描述，也不能证明独立 Likeit 沿用这些值是否符合应用约定。当前证据不足以给出“服务器保证接受”的 Likeit device JSON；应以该应用对应的公共参数约定为准。

### 主会话真实探针回报

主会话随后报告：向 `openapi.music.163.com` 的匿名登录路径提交签名请求，设备使用自己的 Likeit 身份，`deviceType=openapi`、`os=macOS`、`channel=likeit`、`brand=Apple`、`model=arm64`、`appVer=0.1.0`、本机 `osVer` 和新建持久设备 ID，未传 `clientIp`。返回 HTTP 200、业务 400，消息为“公共参数校验失败，请检查os/channel/brand等是否符合约定”。研究子任务未接触这次请求或真实凭据。

该回报表明公共参数受应用约定约束，不能证明具体哪个字段不合规，也不能排除遗漏字段（如 `clientIp`）；校验先后顺序未知，不能据此宣称网络验签通过。追加检索未发现官方 `b3010`/`a3010` 前缀定义或三字段约定；已检查源码也没有按这两个前缀分支。为得到成功而把三字段改为 `ncmcli` 缺少针对该应用的依据。需要的是脱敏的官方参数约定，无需追加秘密值；核实后若它们确为协议固定值，遵从固定值与伪造物理设备是不同问题。

## 匿名 token、扫码与最小下一步

没有取得证明匿名 token 可调用用户应用的 search、普通歌词或逐字歌词的官方权限说明。官方 CLI 的 manifest 同步要求用户已登录，清单 `auth_required=true` 的命令也要求用户登录；`false` 时省略 token。这是 CLI 控制流，不能倒推所有歌词 API 一定要求实名 token，也不能把匿名 token 获取成功当作歌词权限验证成功。[已有清单证据](netease-openapi-lyrics-research.md#离线补充动态发现搜索与普通歌词)

下一步按证据边界推进：

1. 从该应用对应的官方接入说明确认认证 host、匿名登录权限、device 字段的必填性和允许值，以及目标歌词/搜索接口的 token 要求。人类只需提供脱敏的应用类型/权限/参数说明，不需要发送秘密值；现有资料站正文访问限制见已有研究第 43–47 行，未绕过该限制。
2. host/device 规范确认后，可由主会话用用户授权的本地配置，向**已确认 host**发送上述一次匿名 POST，使用 Likeit 自己持久化的 deviceId。记录 HTTP 状态、业务 code/message 和 token 字段是否存在，避免输出 token、私钥、完整签名请求。匿名登录会签发凭据，不能称为“没有状态影响的普通只读探针”。
3. 只有目标接口官方要求用户授权，或采用目前 CLI 的已登录 manifest/search 路径时，才安排二维码授权。用户在网易云 App 扫码并点击确认是需要人的步骤；无需把账号密码交给 Likeit。匿名接口权限不明确时，先确认或明确标记测试性质，不宣称必须扫码。
4. 不带凭据/参数访问路径最多证明路由存在；即使返回“参数为空”，也不能验证 host 等价、签名、应用权限或 device 合法性。若要开展真实鉴权，凭据使用和结果处理仍由主会话负责。

未修改产品、测试、计划、验收契约或冻结清单；未运行测试。本文由研究子任务保存，提交由主会话统一安排。

## 主会话后续：个人开发者入口已确认

用户随后明确确认凭据来自官方个人开发者申请入口。该入口与官方 `ncm-cli-setup` 安装说明链接一致，补上了此前缺失的应用来源证据。主会话据此验证个人开发者的官方客户端协议profile：`deviceType=openapi`、`os/channel/brand=ncmcli`，保留独立Likeit设备ID、真实架构/系统版本和既有其他字段。此处三项值按协议标识处理，不解释成物理硬件/操作系统，也不推广为任意IoT应用的通用约定。

在 `https://openncm.music.163.com` 上，第一次请求从先前公共参数错误推进为业务2511“缺少clientIp参数”；补入本机当前网络接口的真实IPv4地址后，匿名认证返回 HTTP200/业务200，存在accessToken、refreshToken、expireTime、scopes。签名仍由产品的 `openAPISignature` 执行，私钥未上传。凭据及响应继续只保存在仓库外0600文件。

二维码接口随后返回业务200，主会话在本机生成并向用户展示二维码，等待手机网易云确认。匿名token请求CLI manifest返回业务301“用户未授权当前接口”，因此该应用此次确实还需要用户授权才能验证既有manifest路径。该结论仅针对本次应用和请求，不能推广成所有歌词接口的权限规则。

截至上述步骤，匿名认证及二维码获取已真实验证；用户授权、用户token、manifest/search/歌词，以及默认openapi网关与openncm网关的token兼容性仍未确认。没有更改产品代码或旧测试，也未激活运行时官方歌词配置。
