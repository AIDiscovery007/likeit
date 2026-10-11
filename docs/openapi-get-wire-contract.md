# O2 追加：GET 线上的编码语义

Given 关键词、device、token 或 Base64签名包含 `+`；When GET 公共参数进入 URL；Then 服务端按标准 query/form（URLSearchParams）解码得到的值必须与签名原文一致。只在客户端用 URLComponents.queryItems 解码并验签不足以证明这一点：裸 `+` 会被 form 解码为空格。

此项补充冻结的“签名覆盖实际发送字段”要求，不修改任何既有测试。O2 handoff 的 URLQueryItem 编码是构造方式提示，仍须把值内 `+` 转义为 `%2B` 或使用等价的正确 form 编码；`&`、`=`、非ASCII等也必须保持值。官方客户端使用 URLSearchParams，依据仍是已记录的官方包研究。

独立验收通过 URLProtocol 截获产品真正构造的绝对 URL，再由 Node URLSearchParams 解码和 Node crypto验签；没有真实网络、账号或凭据。开发前尚无 DesktopOpenAPILyrics.swift，测试预期 red，协调者负责执行。
