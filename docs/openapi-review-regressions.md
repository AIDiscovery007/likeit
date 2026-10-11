# O2 独立 review 新增回归

基线 `cdf4e69`，协调者原全量205项tests通过，48项冻结摘要未变；没有因此跳过review。Standards轴无发现；Spec轴提出 numeric精度和required/fixed顺序，协调者另发现普通歌词alias兼容问题。新增此契约与测试，不修改旧冻结文件。

1. **精确歌曲 ID**：Given JSON原文 originalId=1377163127.00000001；When 匹配整数1377163127；Then 拒绝。不能先舍入成Double再确认整数。协调者已通过真实provider+离线URLProtocol复现错误成功。
2. **普通歌词有效原文字段**：Given data.lyric是null或空字符串、data.lrc.lyric含合法原文LRC；When逐字歌词无结果而回退；Then使用后者。协调者已复现两种输入均未显示有效歌词。依据已检验的官方Js.getLyrics使用 `data.lyric || data.lrc?.lyric`，见研究报告与官方0.1.7包，不是猜response。数字/对象等错误lyric类型仍须失败，不能掩盖；null/空且无有效第二字段为无同步歌词。
3. **清单已提供必填固定值**：Given POST非identity必填body参数scene，fixed_params提供正确string值且不冲突；When执行命令；Then该固定值满足required并实际发送。这是对原“required且无已知值才失败”的协调决策：清单内合法固定值属于已知值。固定值仍须符合参数类型；keyword/songId仍必须来自声明且实际传输的provided输入，不能fixed-only或覆盖成另一个值。GET固定body参数的拒绝规则保持。

开发者只修改产品与重建产物，不运行或调整本回归/原测试；协调者负责红绿验证。全部使用公开测试key和原创一行歌词，不碰真实配置、账号、网络或音乐UI。

开发前运行 `node --test acceptance/openapi-review-regressions.test.mjs`：5项行为中4项失败（fractional、null original、empty original、fixed），fixed wrong type通过；含父测试为6 tests、1 pass、5 fail。编译成功，失败是已复现的产品行为。
