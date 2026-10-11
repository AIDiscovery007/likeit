# 官方歌词接入验收记录

本迭代用户已确认自有应用与接口权限，先要求开发、随后提供了自有应用凭据。未复用先前文档样例 token/sign，未读取账号缓存，未对音乐 UI、收藏、播放和系统权限做任何操作。离线验收与后续真实认证探针分别记录如下。

## O1：签名与响应解析

- 冻结：`5fcca2c`，`docs/openapi-lyrics-core.sha256`，开发前缺少产品文件的 red 已记录。
- 初始实现：`6a2eb0e`，仅新增 `native/OpenAPILyricCore.swift`；开发者只运行 arm64/x86_64 产品 typecheck，没有写/改/跑测试。
- 协调者运行：原17项行为断言全部通过（Node报告18 tests，含父测试）。两组 RSA 签名来自独立 Node crypto 和显式规范字符串；Swift signer 与其一致。
- Standards review：无发现。Spec review：1个问题——可选 PKCS8 attributes 内部无验证即被丢弃。协调者用畸形 A0 01 FF 复现 Node拒绝、Swift接受。
- 新增回归冻结：`f4051d7`；没有修改原测试。开发者修复 `c21c3ab`，只删除忽略属性的一行，明确仅支持无 attributes 的 PKCS8 profile。
- 协调者复跑原测试与新回归：19/19 Node tests通过；签名/解析及回归清单哈希均通过。

## O2：配置、provider 与桌面集成

- 冻结：`1d823aa`，`docs/openapi-lyrics-provider.sha256`，41项Swift行为场景，另对实际请求字段进行Node独立验签；开发前缺产品文件的 red 已记录。
- 实现由原独立 high 开发会话完成：初版 `cdf4e69`，随后 `b6f3f7c`、`614f55d`、`4ec48d7`、`f49bf65`、最终产品 `f673898`。
- 方案保留原公开搜索完整性、元数据唯一匹配和详情复验；取得 numeric ID 后只接受官方显式 originalId 对应的32hex ID。UUID没有被假冒成歌曲ID。

## 独立review与修复

- `cdf4e69` 全量205/205通过。Standards轴无发现；Spec轴指出分数ID舍入误匹配和固定参数不能满足required两项。主会话又对照官方 `data.lyric || data.lrc?.lyric` 复现null/空原文阻止有效嵌套原文的兼容问题。
- 新增冻结 `ea4a96d`，5行为中4项red；开发者仅修产品。`b6f3f7c` 全量209/211，fractional仍失败：平台实测NSNumber混合比较会再次舍入，静态review没有充分暴露这一点。
- 协调者继续检查同源状态码，新增 `0ad260c`：code=200.00000000000001在core/manifest/search/word/ordinary五路径全red。`614f55d` 改Decimal比较后211/217通过；JSONSerialization在读取17位数值时已损失精度，故比较阶段无法恢复。
- 最终 `4ec48d7` 从原始Data用JSONDecoder保留Decimal，四处整数校验复用，固定参数改同类型比较。新增原文ID与fixed冲突用例在独立临时目录回放614f55d均red，在最终版本green；没有修改任何旧断言。
- 后续 Standards 指出 Decimal 最长精度边界，主会话实测超38位 mantissa 仍被舍入。新增冻结 `fc119be`，先记录1个行为red、2个green；开发者 `f49bf65` 增加数值token范围检查，主会话224/224通过。
- 最后 Standards 指出原始字节扫描与 Foundation 自动UTF-16转码不一致。主会话探针证实 UTF-16/UTF-16LE 绕过，并在 `8cad54a` 先冻结新增编码回归（2行为red、2行为green，含父项5 tests、3 fail）。开发者 `f673898` 在入口拒绝原始NUL；合法UTF-8转义字符串保留。
- 最终双线review仅复核最后修复：Standards确认其已关闭所报告编码风险；Spec确认符合新增契约，均无新增发现。审查只读，实际运行结果由主会话独立提供，真实平台验证仍不在静态review结论内。

## 最终离线验收

- 协调者在 `f673898` 运行 `node --test acceptance/*.test.mjs`：**229/229 tests通过，无fail/skip/cancel**。涵盖旧收藏/彩带/动效/沉浸路径及新增官方签名、配置、实际桌面分支、ID、fallback、取消、错误、实际GET编码、精度与响应编码回归。输出留存于本机 `/tmp/likeit-openapi-release-final.tap`。
- 所有新旧冻结文件保持不变，共61项、14份独立清单。新增用例均由协调者编写/执行，开发者没有跑测试，没有为迁就实现修改旧断言。
- 原生双架构编译与lint由开发者完成；协调者独立核对10项source和10项bundle摘要、严格深层签名及arm64/x86_64架构。随后 `npm run build` 成功更新本机扩展，安装包10项摘要及签名再次核对一致。应用不包含测试PEM或真实配置。
- 尚未验证真实歌词请求成功、当前歌曲显示或逐字高亮；本轮使用 `data.lrc` 逐行同步，不推测逐字时间。未触碰播放、收藏、系统音频权限和现有动效偏好。

## 自有凭据的首次真实认证

用户随后提供自有应用凭据，并授权本地保存且不得提交Git。主会话将其保存在仓库外 `~/Library/Application Support/Likeit/netease-credentials-20261011/`，目录0700、文件0600；用OpenSSL派生公钥比对，确认所给公私钥匹配。不在本文或产品中记录实际appId、secret、密钥、签名或token。

按照官方CLI已查明的协议，主会话使用产品的 `openAPISignature`、新建且持久化的Likeit设备ID与真实macOS描述，分别向 `openapi.music.163.com` 和 `openncm.music.163.com` 的匿名登录endpoint发送一次RSA签名请求。两个网关均为 HTTP200 / 业务400，返回“公共参数校验失败，请检查os/channel/brand等是否符合约定”，没有accessToken。未提交私钥或app secret。匿名认证属于尝试签发凭据的操作，不称为无状态只读请求。

该响应不能证明签名已被服务端接受，不能确定单个错误字段，也不能证明网关的鉴权合约等价。主会话已请求用户提供该应用登记的device公共参数约定，没有改成CLI身份碰运气。尚未生成或启用运行时 `netease-openapi.json`，现有无配置公开歌词行为保持。官方认证证据见 `docs/netease-openapi-auth-research.md`。

真实API尚未接通。应用的公共参数、用户token、动态清单、真实参数schema、官方双ID命中、当前歌曲歌词显示与token失效行为仍待验证。离线测试通过与本地密钥匹配都不等于真实歌词请求成功。
