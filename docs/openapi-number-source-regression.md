# 精度根因：必须在 JSON 解码时保留数值

`614f55d` 全量217 tests结果为211 pass/6 fail：旧高精度ID回归已通过，五条状态码路径仍失败。实际平台探针表明：JSONSerialization直接把200.00000000000001、1377163127.0000001解码成普通NSNumber整数200、1377163127；此时Decimal helper无法恢复原值。JSONDecoder直接读取Decimal能保留这两个原文值。另实测NSDecimalNumber(20.0000000000000001).isEqual(NSNumber(20))返回true，fixed冲突校验也受影响。

新增Given/When/Then，不改既有冻结项：

- Given原始originalId=1377163127.0000001；When匹配整数ID；Then拒绝，在search后停止，不请求word。
- Given清单将number类型limit固定为20.0000000000000001；Whenprovided limit为20；Then认定冲突，在manifest后停止，不执行search。未声明type的数字冲突也应按相同精确比较处理。

协调方案：本次官方响应从原始Data解码，数值保留Decimal，避免JSONSerialization先舍入；旧公共resolver与string-map配置读取不变。固定参数的scalar相等使用明确类型和Decimal比较，拒绝不同数值/类型，不用混合NSNumber.isEqual。全部验证由协调者运行，开发者只修产品和重建，真实账号/网络/UI仍不涉及。

新增用例编写期间，开发者按已确认根因独立提交了4ec48d7。因此协调者另外将614f55d的四个所需产品源码用git show复制到临时目录，以同一份新测试回放旧版本：两行为全red（含父项3 tests、0 pass、3 fail）；4ec48d7上同测试全green。没有改动旧checkout或任何测试断言。随后全量220/220 tests通过；本文件与新增测试现在冻结。
