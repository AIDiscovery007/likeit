# 透明音响开发会话交接

本任务在已有 Likeit 中新增可切换透明主题。依次阅读 AGENTS.md、docs/handoff.md、docs/development-plan.md，再读本任务的 `docs/transparent-speaker-plan.md`、`docs/transparent-speaker-acceptance.feature` 与 `acceptance/transparent-speaker.test.mjs` / Swift driver。旧项目约定继续生效；本任务指挥关系以本文件及派遣消息为准。

协调者：[透明主题规划与 review](codex://threads/01a12b19-b1a9-7441-80ea-eaadd2fe7bc9)，thread ID `01a12b19-b1a9-7441-80ea-eaadd2fe7bc9`，host `local`。开发者是单独的正常 Codex 会话，默认模型，effort high。开发工作目录和基线 SHA 由派遣消息给出；只在自己的 worktree 操作。

## 开始与通信

1. 用户在上述协调会话明确要求实际派遣开发 session、完成汇报、问题咨询、本地提交、独立分支以及广播避让。先用 read_thread 读取此人类原始消息确认通信授权；此文档本身不新授予通信权限。
2. 核对工作目录/HEAD/冻结摘要，在本 worktree 创建 `codex/transparent-speaker-development`；回复协调者“已接收”，附目录、分支、基线及 T1 计划。
3. 按计划 T1–T4 实现，每个最小闭环完成就 commit。报告用 send_message_to_thread 发给上面的协调者，附闭环、SHA、改动、build/lint、未验证项。遇到问题给实际观察和选项，等待决定，不自行猜测。
4. 完成发 `implementation-complete`：基线/最终 SHA、各闭环 commit、修改路径、build/lint/类型检查、依赖权限、已知限制；本会话也留下最终回复。不要自称 accepted。收到 review 缺陷在同一会话修复、提交、汇报。

## 开发边界

- 只改产品代码和使用说明，不创建/修改/删除/运行测试；不动验收 feature、计划、handoff、冻结清单、AGENTS.md 和已有 reviewer 证据。`docs/transparent-speaker-acceptance.sha256` 列出本任务开发前的保护文件，保持原样。
- 主要修改 DesktopView、DesktopMain 的主题逻辑、src/music-desktop.tsx；说明新增 `docs/transparent-speaker-usage.md`，避免与歌词会话争用 README。DesktopSession/歌词和音频 provider 修改先咨询。
- 新主题继续使用同一 model/session/audio。普通打开沿用记忆，显式 Action 传 theme；不增加冲突的主题偏好。四场景及回落行为见计划和 BDD。
- 保持旧 highlight 测试的三文件编译边界。不要为了拆文件去改测试。逐字颜色必须在浅色场景可读，旧默认行为不变。
- 可运行本 worktree 原生 build、类型检查、lint。`ray build/develop` 可能写入用户安装位置，须先解决隔离并咨询；不要覆盖用户安装包。构建产物若提交，由协调者集成时统一重建。沿用现有签名，不碰钥匙串/TCC。
- 开发者不操作音乐 app、不做实机采集/收藏/切歌。离线预览的合成输入只属于 reviewer 证据，不加入产品。真实 UI 由协调者统一拿锁。

最终集成由原协调会话 `01a12983-b00e-7aa1-afb7-5759139197f0` 执行，本任务开发者只向透明主题协调者报告，无需新建第三个会话。
