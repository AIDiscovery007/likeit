# 社区歌词交付 review — 2026-10-11

结论：**implementation-complete / automated-reviewed，代码已本地合并；尚未标记完整 real-device accepted。** 初次review没有覆盖安装；随后由音频协调会话安装包含社区歌词和可见性修复的版本，并完成下述有限实机复核。社区协调会话未操作网易云播放/收藏、未更改签名身份/钥匙串/TCC。

## 提交与隔离

- 开发session：[实现 AMLL 与 LRCLIB 社区歌词](codex://threads/01a12ac1-211d-7713-a22e-46e33031b479)，默认模型、high effort。
- 开发目录 `/Users/qiaochao/.codex/worktrees/bb6b/likeit`，分支 `codex/community-lyrics-development`。
- 协调目录 `/Users/qiaochao/.codex/worktrees/community-lyrics/likeit`，分支 `codex/community-lyrics`。
- C0冻结：`743066106c7e760b95ac5dc0d72dcea53ed66d97`。C1 `8c58185`、C2 `ae10d7c`、C3 `cd1d102`、C4 `98f4773`、R1 `b21a032`、C5 `c34ec6d`、R2 `4ac0afc1392fe8858ab31caf625cdd094b5f13bc`。
- 合并产品提交：`bacf3d3f8621ccf0b03685100433adbd59f25c3a`。包含音频产品 `23ffa7a` 和验收文档 `622892e`；二进制/manifest冲突通过合并后的完整源码重新构建解决，未选用任一旧分支产物。
- 用户已取消PR，只本地branch/merge，不push、不发布。主checkout由原音频协调会话执行最终ff-only合入，避免两个会话同时写目录。

## 固定验收

原有所有冻结文件原样保留。最终20份sha256清单、85个条目内容校验无差异。开发者从C0到最终提交只修改产品、构建产物和README，没有写/改/删除/运行测试。

协调者执行 `node --test acceptance/*.test.mjs`：**344 tests，344 pass，0 fail，0 skipped，0 todo**。包括原267项、社区顶层与51行为检查、R1六项、R2十六项。原始输出：[final-344.tap](review-evidence/community-lyrics-2026-10-11/final-344.tap)。

初始C0两项顶层红灯已记录；后续R1有效容器失败、R2重复词定位失败均先由协调者追加合成回归确认红灯，再由开发者修产品。原51项及旧验收从未修改。R2红灯记录：[highlight-red.tap](review-evidence/community-lyrics-2026-10-11/highlight-red.tap)。

构建与静态检查：

- `python3 scripts/build-desktop.py`：arm64/x86_64通用app构建、codesign strict通过；合并后的所有源码摘要、包内文件摘要与DESKTOP-BUILD.json一致。
- `npx ray build --output ./node_modules/.cache/likeit-community-build --exit-on-error` 与 `npm run lint` 通过。构建留在隔离worktree，没有写入Raycast安装目录。
- `git diff --check` 通过。无新增第三方依赖或系统权限。
- 当前生成包仍为ad-hoc hardened runtime；固定签名身份由音频协调会话另行处理，本报告不声称跨版本授权连续性已验证。

## Standards

独立Standards轴检查固定差异 `7430661...98f4773`：无实质硬性违规，无需整改的维护风险。未改验收/冻结资料，未新增依赖/权限/播放器控制；无猜测性通用框架。网络、取消、超时与缓存边界符合计划。后续修复仍保持这些边界。

## Spec

独立Spec轴发现1项P2：全文子串定位会让重复词高亮到错误位置。开发者R2改为解析时记录真实UTF-16范围，渲染时校验范围、顺序和内容并映射Swift索引，删除子串猜测；16项新回归通过，Spec reviewer复核 `b21a032..4ac0afc` 确认关闭。

协调者另通过真实API发现R1：合法TTML div容器时间被误拒绝。已按明确决策支持body/div有界绝对时间与合法重叠，并保留倒序、缺端、负数、越界拒绝；追加6项回归通过。

两轴汇总：Standards 0项；Spec 1项P2已关闭；另行发现的R1也已修复，当前无未处理代码缺陷。

## 真实数据与原生渲染证据

只读实测的商业歌词仅在内存解析，没有保存歌词全文或复制为fixture。

- AMLL `ncmMusicId=442867526`：真实HTTP200；最终生产解析器得到59主行、505个主词时间段、58行内翻译。505不包括背景人声/空白，不能与原文件所有timed span数量直接等同。
- 对Die For You / The Weeknd / Starboy / 260秒，实际调用完整CommunityLyrics且**不预填可信ID**：最终严格匹配LRCLIB成功，60行LRC、0逐词。此记录证明自动后备路径可用；不能声称该元数据路径必然选中AMLL。详情：[live-api-summary.json](review-evidence/community-lyrics-2026-10-11/live-api-summary.json)。
- 用最终生产parser和DesktopView/NSHostingView渲染原创合成内容，检查逐词明暗、独立空格、中文翻译、前后句、长句与纯文本区域。截图：[逐词双语](review-evidence/community-lyrics-2026-10-11/timed-native.png)、[长句](review-evidence/community-lyrics-2026-10-11/long-native.png)、[纯文本](review-evidence/community-lyrics-2026-10-11/plain-native.png)。这些是合成原生视图截图，不是当前歌曲或实际播放器同步证据。

## 未验证项与后续

本次看到安装版Likeit Desktop仍在运行，为遵守隔离约定，没有替换安装版或启动同bundle的新实例，也未修改当前网易云播放。故实际Raycast设置→新桌面、真实逐词音频同步、暂停/seek/换曲/换源、纯文本实际滚动到末尾、最终新包Esc/Cmd+Q、长时间性能、Intel/macOS14.2实机仍未验证。已有离线clock/generation检查与静态审查不能替代这些实机路径。

安装与实机验收应由协调者在取得音乐/UI操作窗口后单独完成，保留当前签名决策，不将本次自动化通过包装成全部实机验收。用户可在更新安装后将“沉浸桌面歌词来源”改为“社区歌词（AMLL / LRCLIB）”；默认网易行为保留。

## 安装后有限实机复核

基线：主分支 `dabd955`，产品可见性修复 `3dcb9ec`。音频协调会话已安装包含社区歌词的版本，报告359/359检查通过，并退出Likeit后释放UI锁。社区协调会话取得UI锁，在原安装包上进行以下检查，没有再次安装或构建。

- 使用 `likeit-desktop://open?mode=off&lyricsSource=community` 启动，原生可访问性树显示当前歌曲Designer / Graham、LRCLIB完整歌曲信息匹配、逐行歌词、已暂停，以及“桌面动效已关闭 · 不采集音频”。真实歌词仅在内存观察，未保存全文或截图。
- 在同一运行实例以URL切到 `lyricsSource=netease`：旧LRCLIB/AMLL归属消失，经历匹配状态后显示原网易路径“歌词按歌曲信息匹配”；歌曲保持不变且仍暂停。
- 再以URL切回 `lyricsSource=community`：匹配期间旧来源状态被清除，完成后恢复社区归属，没有失败状态；歌曲保持不变、仍暂停、音频采集保持关闭。
- 用原生UI键盘动作发送Esc。随后可访问性读取返回进程不存在；`pgrep`确认Likeit Desktop及指定now-playing观察器进程没有存活。未用进程强杀代替退出检查。

本轮补充了实际安装包的当前歌词呈现、运行中双向换源和Esc退出证据；呈现通过原生可访问性树核验，未重新进行截图视觉评审。没有触发网易云播放/暂停、seek、切歌或收藏，没有改Raycast持久偏好。真实逐词音频同步、主动暂停/seek/换曲、Raycast设置入口、纯文本滚动到末尾、Cmd+Q、长时间性能与Intel/macOS14.2实机仍未验证。原有冻结测试、断言和验收契约保持不变。
