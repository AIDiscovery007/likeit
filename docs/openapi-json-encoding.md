# JSON 编码边界回归

Given 官方响应数值超出已冻结的 38 位 mantissa 支持范围，When 响应使用 UTF-16、UTF-16LE 或 UTF-32，Then 必须拒绝，不能因原始字节中的 NUL 重置扫描器而接受被舍入的 code。

Given UTF-8 JSON 含合法转义字符串 `\u0000`，When 解码有效 code 与同步原文，Then 原文仍正常返回。拒绝原始 NUL 不得误伤转义字符串。

主会话在 f49bf65 的独立本机探针中确认 UTF-16 与 UTF-16LE 被接受，UTF-32 已拒绝。Foundation JSONDecoder 可自动转码，因此逐字节扫描需拒绝原始 NUL；网络 JSON 的 UTF-8 内容没有合法原始 NUL。新增测试先于产品修复冻结，不修改任何旧测试。开发者仅修产品并重建，测试由主会话执行。
