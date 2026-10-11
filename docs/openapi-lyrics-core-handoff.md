# 网易官方歌词接入：闭环 O1

协调者先冻结，独立 high 开发会话只实现产品并提交。旧测试与29项冻结文件不得修改；开发者不写、不改、不运行测试。不 push、不发布、不碰音乐 UI、权限、账号配置。

本轮用户已确认有自有应用和歌词接口权限，要求先开发、凭据稍后补。完整方向是可选的官方歌词 provider：显式本机配置，官方 ID 自动映射，用户给出的逐字 endpoint，先复用 data.lrc 的全屏逐行展示。旧路径在未配置时保持原行为。数字原始ID、32位hex官方ID和MediaRemote UUID不互换。搜索路径和返回完整性仍在核实，不得猜测，不以手填逐首ID或固定示例歌曲冒充自动路径。

O1 仅新增 `native/OpenAPILyricCore.swift` 的无网络核心，不提前改桌面入口、现有歌词实现、构建产物或配置。采用以下 internal 接口（协调者的独立编译驱动使用它们）：

```swift
func openAPISignature(parameters: [String: String], privateKeyPEM: String) throws -> String
enum OpenAPIWordLyricResult {
    case lines([LyricLine])
    case noWordLyrics
    case noSynchronizedLyrics
    case apiError(Int)
    case malformed
}
func decodeOpenAPIWordLyrics(_ data: Data) -> OpenAPIWordLyricResult
```

签名依据：网易官方 `@music163/ncm-cli@0.1.7`（MIT），已核验npm SHA-512；其 `qu` 排除 sign/null/undefined/空字符串，将其余值转字符串，按参数名 localeCompare 排序，未编码的 key=value 以 & 连接。`Hu` 使用 PKCS8 PEM、crypto.createSign('SHA256')、Base64 RSA 签名。我们接口只接受字符串参数；测试覆盖固定公共参数名（均ASCII）以及非ASCII值。支持 `-----BEGIN PRIVATE KEY-----` 的 RSA PKCS8 PEM；不要调用CLI、OpenSSL子进程或网络签名服务。使用系统 Security API 或同等本地原语。不要把研究用 CLI 或其混淆代码加入产品依赖。

签名的PKCS1 v1.5 padding和UTF8与Node默认一致；已知答案由协调者用临时生成的专用测试私钥和独立Node crypto计算。夹具私钥不是用户凭据。空或无效PEM应throw，错误不含私钥正文。

响应解析：最多1MiB，顶层必须对象，code必须整数（200.5不接受），200时必须有data；显式null为noWordLyrics；data为对象时lrc若为字符串则交现有parseLRC处理。有非空时间行时返回lines（保留现有空时间行清句行为）；空/缺失lrc或只含翻译/逐字数组为noSynchronizedLyrics；lrc为其他非null类型或data结构错误为malformed。非200整数为apiError，仅保留码；不传播message/msg。不要擅自推算suspend/逐字时间。

O1提交后向协调者汇报SHA、文件、静态构建情况和未知项，等待测试与后续O2契约。可单独swiftc typecheck验证产品构建，但不编译或执行acceptance驱动。所有协议疑点先问协调者。
