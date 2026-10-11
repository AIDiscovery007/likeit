# O2 开发前基线

2026-10-11，产品基线 `6a2eb0e`，O1 封装修复独立处理。开发者尚未获准实现 provider。

- 协调者用 `/tmp` 的仅接口空实现 typecheck 新 Swift 验收驱动，确认驱动类型正确；没有把空实现放入产品，也没有据此报告任何功能通过。
- `node --test acceptance/openapi-lyrics-provider.test.mjs`：顶层1项失败，缺少尚未实现的 `native/DesktopOpenAPILyrics.swift`。这是预期开发前 red。
- 实现后驱动必须执行41项行为检查，另由 Node crypto 对实际发出的签名字段独立验签。使用 URLProtocol 截断所有网络，运行真实 provider 与 DesktopLyrics 集成链；测试不读取默认用户配置，不使用文档样例凭据，不接触播放器 UI。
- 范围包括配置、双ID映射、受限清单、空歌词回退、错误、取消/替换、容量约束以及未配置/已配置/身份不完整的实际 DesktopLyrics 分支。传输 deadline、禁重定向、凭据不落日志/argv另由代码review核对；这不是已完成的真实接口验收。
- 原有测试及 O1 已冻结文件完全不改，用户凭据稍后补齐。真实授权清单/schema、歌词成功响应与当前歌曲显示仍待后续验证。
