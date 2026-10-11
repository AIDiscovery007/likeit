# 社区歌词 review 追加回归

## R1 合法的带时间 TTML 容器

2026-10-11，协调者在 C1–C3 冻结的51项行为通过后，用生产parseCommunityTTML读取真实AMLL `ncmMusicId=442867526`：HTTP200，51690 bytes，解析0行。只内存读取并输出结构统计，不存商业歌词正文。

原因：真实数据59个div均带合法begin/end，内部p/span时间本身合法；实现validTimes仅允许p/span具有时间属性，把标准容器分段错误拒绝。示例结构是div begin=28.972 end=33.004，内含对应p。此故障应修实现，原51项及其冻结清单不改。

协调决策：支持body/div的可选完整begin/end，使用同一绝对媒体时钟，不累加父时间；有时间时必须同时存在、有限非负、end>begin，子行不得超出有界祖先容器；兄弟容器/行可以合法重叠。保留原词区间、XML资源和namespace限制。缺失容器时间时沿用现有行为，不制造时间。只有一个时间属性、倒序、负数和越界仍拒绝整份文件。

新合成回归先在当前实现上记录红灯，再交开发者修复；无真实歌词fixture、不削弱旧检查、不改现有冻结测试。命令：`node --test acceptance/community-lyrics-review-regressions.test.mjs`。修复后另做真实接口只读兼容验证；这仍不代表播放器实时同步已验证。
