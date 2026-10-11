# 官方歌词接入验收记录

本迭代用户已确认自有应用与接口权限，但要求先开发、凭据稍后补。全程未复用用户贴出的文档样例 token/sign，未读取账号缓存，未对音乐 UI、收藏、播放和系统权限做任何操作。

## O1：签名与响应解析

- 冻结：`5fcca2c`，`docs/openapi-lyrics-core.sha256`，开发前缺少产品文件的 red 已记录。
- 初始实现：`6a2eb0e`，仅新增 `native/OpenAPILyricCore.swift`；开发者只运行 arm64/x86_64 产品 typecheck，没有写/改/跑测试。
- 协调者运行：原17项行为断言全部通过（Node报告18 tests，含父测试）。两组 RSA 签名来自独立 Node crypto 和显式规范字符串；Swift signer 与其一致。
- Standards review：无发现。Spec review：1个问题——可选 PKCS8 attributes 内部无验证即被丢弃。协调者用畸形 A0 01 FF 复现 Node拒绝、Swift接受。
- 新增回归冻结：`f4051d7`；没有修改原测试。开发者修复 `c21c3ab`，只删除忽略属性的一行，明确仅支持无 attributes 的 PKCS8 profile。
- 协调者复跑原测试与新回归：19/19 Node tests通过；签名/解析及回归清单哈希均通过。

## O2：配置、provider 与桌面集成

- 冻结：`1d823aa`，`docs/openapi-lyrics-provider.sha256`，41项Swift行为场景，另对实际请求字段进行Node独立验签；开发前缺产品文件的 red 已记录。
- 实现派给原独立 high 开发会话，由协调者负责后续测试与review。
- 方案保留原公开搜索完整性、元数据唯一匹配和详情复验；取得 numeric ID 后只接受官方显式 originalId 对应的32hex ID。UUID没有被假冒成歌曲ID。

真实授权请求尚未验收。特别是应用能否取得动态清单、真实参数schema、官方双ID命中、当前歌曲歌词成功显示与token失效行为，仍需用户补齐本机配置后验证。通过离线测试不表示真实API已经接通。
