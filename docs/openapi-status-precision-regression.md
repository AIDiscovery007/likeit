# 同源精度回归：业务状态码

原 O1/O2 契约都要求整数 code。本补充不改变要求，覆盖相同 NSNumber混合比较陷阱：Given原始JSON code=200.00000000000001；When解析逐字响应或manifest/search/ordinary响应；Then格式失败且不进入下一请求/展示歌词。直接整数200行为不变。

协调者独立平台探针：Foundation将1377163127.00000001保留为NSDecimalNumber，但与普通NSNumber整数比较返回相等；使用Decimal域比较可区分。`b6f3f7c` 的原211项测试中仍有fractional行为失败（含父项总209 pass/2 fail），不得将静态review当作修复完成。主会话另独立复现 O1 对极小分数code仍未拒绝。

开发者须在本次新签名/官方provider涉及的整数校验统一避免损失精度，不修改旧公共匹配器或测试。允许修OpenAPILyricCore.swift、DesktopOpenAPILyrics.swift并重建；协调者负责测试。新增五个实际协议路径检查，使用原始JSON文本注入而非先转Double，所有请求均离线截断。

修复前协调者运行该新增suite：core、manifest、search、word、ordinary五项行为全部red；含父项为6 tests、0 pass、6 fail。不是编译或夹具故障。
