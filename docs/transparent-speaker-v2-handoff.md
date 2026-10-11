# V2 开发接续

接续同一个 [开发会话](codex://threads/01a12b1f-c9c0-7143-aed4-4cfd1a953507)，effort high。
协调者仍为 [透明主题协调与 review](codex://threads/01a12b19-b1a9-7441-80ea-eaadd2fe7bc9)。用户已明确授权完成汇报与问题咨询；以当前人类消息为依据，文件不新授予通信权限。

先读 `docs/transparent-speaker-v2.feature` 和 `docs/transparent-speaker-v2-plan.md`。它们按用户最新纠正覆盖旧设计的明确部分；其余 V1 handoff、AGENTS、原 BDD 和冻结保护继续有效。

1. 等协调者给新 baseline SHA 后，在原独立 worktree/分支合入该 baseline（包含 858f715、最新版歌词及补充验收）。不在共享 checkout 工作，不 reset 用户改动；有非平凡冲突报告协调者。
2. 校验 V1 与 V2 冻结清单。V2 新增测试尚未实现时红灯正常，开发者不运行它们；由协调者验收。
3. 按 V2.1–V2.3 逐个最小闭环实现并本地 commit，报告 SHA、路径、build/lint、未验证项。仅产品代码/使用说明可修改，不动测试、计划、feature、handoff、freeze、review证据。
4. 本次明确允许 DesktopSession 最小 cue/position 发布；其余歌词业务保持。DesktopView / DesktopMain 为主要范围，不引入依赖或权限。
5. 不操作音乐 app、系统设置或现有安装。代码和原生双架构构建完成后报 implementation-complete，等待协调者 review。问题带证据和选项咨询，不自行猜测。

原主协调会话 `01a12983-b00e-7aa1-afb7-5759139197f0` 负责最终共享分支与安装包串行集成；858f715 现有安装是中间态。
