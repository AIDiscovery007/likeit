# O1 开发前基线

2026-10-11，协调会话在产品基线 `1882a31` 上新增独立验收，尚未派发实现。

- `swiftc -frontend -parse acceptance/openapi-lyrics-core-driver.swift` 成功。
- `node --test acceptance/openapi-lyrics-core.test.mjs`：1 个顶层测试失败，原因是产品文件 `native/OpenAPILyricCore.swift` 尚不存在。不是网络、凭证或歌词版权样本失败。
- 完成实现后必须执行 17 个行为断言；RSA 的两个已知答案由 Node crypto 和显式编写的规范字符串独立生成。测试私钥专用于离线夹具，不属于任何用户或网易应用。
- 用户已确认拥有应用与接口权限，但要求先开发，凭据稍后提供。本闭环不发真实签名请求；通过不能代表真实 API 已接通。
- 原有 29 项冻结文件不得改动；本闭环另行加法冻结。后续 provider 集成另立契约。
