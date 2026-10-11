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
- 实现由原独立 high 开发会话完成：初版 `cdf4e69`，随后 `b6f3f7c`、`614f55d`、最终产品 `4ec48d7`。
- 方案保留原公开搜索完整性、元数据唯一匹配和详情复验；取得 numeric ID 后只接受官方显式 originalId 对应的32hex ID。UUID没有被假冒成歌曲ID。

## 独立review与修复

- `cdf4e69` 全量205/205通过。Standards轴无发现；Spec轴指出分数ID舍入误匹配和固定参数不能满足required两项。主会话又对照官方 `data.lyric || data.lrc?.lyric` 复现null/空原文阻止有效嵌套原文的兼容问题。
- 新增冻结 `ea4a96d`，5行为中4项red；开发者仅修产品。`b6f3f7c` 全量209/211，fractional仍失败：平台实测NSNumber混合比较会再次舍入，静态review没有充分暴露这一点。
- 协调者继续检查同源状态码，新增 `0ad260c`：code=200.00000000000001在core/manifest/search/word/ordinary五路径全red。`614f55d` 改Decimal比较后211/217通过；JSONSerialization在读取17位数值时已损失精度，故比较阶段无法恢复。
- 最终 `4ec48d7` 从原始Data用JSONDecoder保留Decimal，四处整数校验复用，固定参数改同类型比较。新增原文ID与fixed冲突用例在独立临时目录回放614f55d均red，在最终版本green；没有修改任何旧断言。
- 最终双线review：Standards无新增发现；Spec确认已确定问题闭合、无新增发现。审查均只读，真实平台验证仍不在其结论内。

## 最终离线验收

- 协调者在 `4ec48d7` 运行 `node --test acceptance/*.test.mjs`：**220/220 tests通过，无skip/cancel**。涵盖旧收藏/彩带/动效/沉浸路径及新增官方签名、配置、实际桌面分支、ID、fallback、取消、错误、实际GET编码与精度回归。
- 所有新旧冻结文件保持不变；最后新增source回归将总数扩为57项，12份独立清单。新增用例均由协调者编写/执行，开发者没有跑测试。
- 原生双架构编译与lint由开发者完成；协调者独立核对source和bundle摘要、严格深层签名及arm64/x86_64架构。应用不包含测试PEM或真实配置。
- 尚未进行本轮真实签名调用、当前歌曲显示或逐字高亮；本轮使用 `data.lrc` 逐行同步，不推测逐字时间。未触碰播放、收藏、系统音频权限和现有动效偏好。

真实授权请求尚未验收。特别是应用能否取得动态清单、真实参数schema、官方双ID命中、当前歌曲歌词成功显示与token失效行为，仍需用户补齐本机配置后验证。通过离线测试不表示真实API已经接通。
