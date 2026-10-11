# 官方歌词闭环 O2：可选配置与完整请求链

先通过 O1 review，再由原 high 开发会话实现。协调者 owns BDD、测试、freeze 和 review；开发者不写/改/删/运行测试，不碰音乐 UI/权限/用户配置，不 push。不改旧冻结行为、匹配器或源身份。

## 范围与身份

新增 `native/DesktopOpenAPILyrics.swift`，接入 `native/DesktopLyrics.swift`，更新 `scripts/build-desktop.py`（纳入 OpenAPILyricCore.swift）、README、无凭据 example、原生构建产物及来源 manifest。其他产品变更先咨询。先研究 docs/netease-openapi-lyrics-research.md。现有 MediaRemote UUID 不提供库歌曲 ID，仍通过原公开完整搜索 + 严格 metadata 匹配 + detail 复验拿 numeric ID。不得放宽任何现有检查。

在既有 detail 通过后分支：未配置继续原公开歌词；配置有效则用本轮 provider；显式配置错误提示配置不可用并不发官方请求。DesktopLyrics.cancel/stop 必须取消 provider；仍由原 generation 与总15秒 deadline 保护，成功提示保留“歌词按歌曲信息匹配”。配置按每次打开桌面读取，修改后退出重进生效。不得静默退回公共歌词掩盖鉴权失败。模板不可写入真实默认配置路径，用户稍后自行填。

## 协调者独立验收接口

```swift
struct OpenAPILyricConfiguration {
    let appID: String
    let accessToken: String
    let privateKeyPEM: String
    let device: [String: String]
    static var defaultURL: URL { get }
    static func load(from url: URL) throws -> OpenAPILyricConfiguration?
}
enum OpenAPILyricOutcome {
    case lines([LyricLine])
    case noSynchronizedLyrics
    case unavailable(String) // safe human-readable message, not raw network/server errors
}
final class OpenAPILyrics {
    init(configuration: OpenAPILyricConfiguration,
         sessionConfiguration: URLSessionConfiguration = .ephemeral)
    func load(originalID: String, keyword: String,
              completion: @escaping (OpenAPILyricOutcome) -> Void)
    func cancel()
}
// Extend DesktopLyrics's default initializer for integration acceptance only:
// init(sessionConfiguration: URLSessionConfiguration = .ephemeral,
//      configurationURL: URL = OpenAPILyricConfiguration.defaultURL)
```

所有生命周期方法/回调在 main；sessionConfiguration 和 configurationURL 仅为内部 URLProtocol/临时配置测试接缝，不暴露用户可变 host 或 URL。同一 sessionConfiguration 应用于公共与官方请求；生产默认仍由原生固定host构造URL。无须通用 transport/SDK。配置默认 `~/Library/Application Support/Likeit/netease-openapi.json`，JSON keys `appId`, `accessToken`, `privateKeyPath`（绝对本机路径）, `device`（非空 string map，不复制 CLI 身份）。JSON/PEM 各<=64KiB、普通非符号链接文件且 POSIX mode 不得有 group/other 位；缺 JSON 才返回 nil，其余配置失败 throw 固定安全错误。JSON 中身份字符串非空，PEM 由 O1 signer 验证可用。无 Keychain/CLI 缓存/环境变量自动搜索、刷新、扫码登录或自动生成设备身份。文档提供 umask 077、外部文件创建/填写方式与移除配置恢复旧路径；例子仅占位符，不含 sample token/key。

## 有界协议

每次 load 独立 generation、取消前次请求；不缓存 manifest/歌词以简化凭据与过期行为。每请求5秒、<=1MiB、整体15秒；URLSession ephemeral，禁止cookie/凭据storage/cache及一切redirect。只固定 HTTPS openapi.music.163.com。签名使用 O1；`timestamp` 毫秒字符串；device/bizContent 各先 JSON 编码成字符串，签这些确切值。GET URLQueryItem 编码，POST JSON（所有公共字段为字符串）。User-Agent 可标明 Likeit，不仿冒 ncm-cli；Referer 可 music.163.com。只发送已有 accessToken，不自动登录/刷新。

1. POST `/openapi/v1/ncm/cli/manifest`，biz `cliVersion:"0.1.7", cachedVersion:"{}"`。0.1.7 是已检验的命令清单兼容版本，不声称运行 CLI。读顶层 manifests；若出现 code 则仅接受整数200。root.sub_resources → name search/song → path索引资源 → methods中name song/lyric。目标描述必须完整、唯一，不猜静态路由。search descriptor 必需；普通歌词 descriptor 仅在 fallback 时校验，缺少它不能阻止有效逐字响应中的 data.lrc 成功。
2. descriptor仅 GET/POST，path只接受 `/openapi/` 开头的 ASCII 字母/数字/下划线/连字符/斜杠，拒绝双斜杠、点、query、fragment、百分号、冒号、花括号。auth_required 若给出必须Boolean；为true时 auth_provider 缺省或 netease，其他拒绝；false时该命令不附token。不执行notice/code，不跟远端URL。
3. parameters array或map；名称必须唯一，位置 query/body，只支持标量string/integer/number/boolean（缺type按普通标量处理），拒绝upload/object/array/path/unknown；只使用声明的已提供参数，非空缺失required则失败。fixed_params只能普通标量map，允许不冲突值覆盖body，不得替换提供的 keyword/limit/songId，GET含body固定值直接拒绝。搜索必须实际发送keyword，歌词必须实际发送songId；GET只query，POST合并query+body。不构造猜测分页/default参数。
4. search提供 keyword、limit=20；trialScene不必冒充tui，有清单required但无已知值则明确失败。响应code整数200；data.songs/data.list/直接array/数字键对象按官方兼容读取，最多100条。originalID只接受正ASCII十进制；候选originalId为正安全整数或规范正十进制字符串；exact equal才选。candidate songId或encryptedId独立32hex验证，二者同现冲突拒绝。绝不采用id fallback。去重相同映射；冲突或无映射 unavailable，不能以首屏宣称歌曲不存在。
5. POST用户提供逐字 endpoint，biz仅 songId。使用O1decoder；lines成功；noWordLyrics/noSynchronizedLyrics才走manifest song lyric；apiError/malformed直接safe unavailable。普通歌词 code整数200，data null或original空为noSynchronizedLyrics；original取data.lyric字符串或data.lrc.lyric字符串，保留空行语义，只有翻译不算。错误/格式不对为unavailable。

未验证真实清单、权限和schema；未知情况下失败必须具体但不含原始敏感数据。凭据到位后再由协调者做真实调用和当前歌曲显示验收。O2离线通过不代表API已通；当前公共metadata resolver仍可能因为候选不完整而拒绝，不能借新provider绕过。

提交前只做产品 build/lint；测试与 live UI 均交协调者。汇报本地SHA、文件、构建、配置文档和未验证项。任何边界冲突先咨询。
