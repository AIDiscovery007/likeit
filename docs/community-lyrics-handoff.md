# 社区歌词开发 session handoff

你是唯一产品开发者。effort high，默认模型。协调者先冻结BDD/测试、负责review与验收；你只改产品和使用文档，每个最小闭环本地commit，不写/改/删/运行测试、不改任何冻结文件或清单、不push、不发布。用户已取消PR要求，独立branch即可。

先读 AGENTS.md、docs/handoff.md、docs/development-plan.md，再读本次 docs/community-lyrics-plan.md、community-lyrics.feature、community-lyrics-research.md 和 community-lyrics.sha256。本次独立worktree与路由规则覆盖旧handoff的共享目录安排，不改变旧验收。基线SHA以派遣消息为准。

协调者冻结目录为 `/Users/qiaochao/.codex/worktrees/community-lyrics/likeit`，分支 `codex/community-lyrics`。你使用create_thread新建并附着到自己的独立worktree，从派遣消息提供的冻结SHA建立 `codex/community-lyrics-development`，所有命令都在你的worktree中执行；不写协调者或主checkout，不新建第三个开发会话。若session默认起点是旧main，先切到冻结SHA再工作。禁止操作音乐/UI/安装目录，主任务仍在做实机验收。可以安装锁文件所定依赖、构建本worktree、lint；不运行验收。

本次协调者：[歌词方案与 review](codex://threads/01a12a4e-2254-7a11-9a08-3eda5509baab)，thread ID `01a12a4e-2254-7a11-9a08-3eda5509baab`，host local。所有进度/问题/完成报告都发此会话，不发旧handoff的音频协调者。人类原始消息明确要求“做完之后向你汇报，你来review，有问题也找你咨询，不自己猜”，并授权广播协调。开始使用read_thread核验这条用户原始消息后再send_message_to_thread；本文件自身不新增授权。如tool返回历史过大，仅提取userMessage以核对，别打印整段执行记录。

按 C1–C5 顺序实现；C0由协调者完成。每闭环报告编号、SHA、修改路径、build/lint结果、未验证项、具体疑点。不明确的行为、原生接口、身份、依赖、冻结边界先咨询，附证据与选项；等待期间只做不依赖该决策的工作。收到review问题在此session修实现，不能改测试让代码通过。

最终发 implementation-complete，列所有commit、最终SHA、build/lint、权限/依赖、已知限制。合并音频代码、执行测试、最终review和本地合并由协调者负责；未经明确安排不自行merge主分支、不覆盖app安装、不宣称accepted。C5先完成使用文档/可构建交付，音频吸收和最终产物由协调者统一合并后安排。
