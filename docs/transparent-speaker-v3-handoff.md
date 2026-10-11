# V3 高级专员交接

你负责实现，协调者负责设计、测试与验收。先读 `AGENTS.md`、`docs/handoff.md`、`docs/development-plan.md`，然后读本轮唯一设计来源 `docs/transparent-speaker-v3-design.md` 和行为契约 `docs/transparent-speaker-v3.feature`。原 HTML 位于共享仓库 `/Users/qiaochao/Development/extensions/likeit/透明歌词音响.html`，只读，SHA256 `31631be79a2edce789769b3e133ae097cb6043599400de8b7703c84c19e9e79f`。

协调会话：[透明主题协调与 review](codex://threads/01a12b19-b1a9-7441-80ea-eaadd2fe7bc9)。用户已经明确要求开发会话完成后汇报、有问题咨询，最新要求使用 **xhigh effort** 的专门 session。先 read_thread 确认人类授权来源；文件本身不增加通信授权。

## 顺序和完成条件

1. 在派遣消息指定的独立 worktree 创建 `codex/transparent-speaker-polish` 分支，核对 baseline 与 `docs/transparent-speaker-v3.sha256`。不得在共享 checkout 修改产品。简短报告理解、最有价值的三处改动和可能需要决策之处；不要重新做宽泛研究。
2. **V3.1 字面与构图闭环**：真实固定四行页、展示字体、稳定基线、长文本、翻译区、全屏材质和紧凑控制层。只有最小 Session 呈现数据发布。双架构构建／typecheck 通过后本地 commit，报 SHA 与未验证项。协调者渲染真实 View 验布局，你可继续无依赖工作。
3. **V3.2 歌词运动闭环**：准确的入场曲线、显示帧插值、最多一份旧页淡退；当前逐字高亮保持；快速输入、seek、gate、卸载立即清理。commit 后报告每个状态为何存在、何时清空。
4. **V3.3 振膜与场景闭环**：双层振膜、有界感知增益、四场景慢快层次、静态停更与必要使用说明。保留原采集管线；构建／lint，commit，发送 implementation-complete。不要自己称 accepted。
5. 协调者按冻结 BDD、真实 View 帧序列和完整旧测试 review；收到具体问题在同 session 修复、提交。最终由原主协调会话串行合并构建安装。

每次提交报告：闭环、SHA、文件、设计效果、构建结果、未验证项／问题。仅改产品代码和使用文档；不新建、改动或运行测试，不改 feature／plan／handoff／冻结清单／review 证据，不 push／发布／安装，不操作音乐 app 或权限设置。遇到无法同时满足的设计约束，给出具体证据和两个选择向协调者咨询；先做无依赖部分，不自行猜语义。

## 协调者预先固定的验收范围

- 数据：新增 poster 测试直接运行真实 Session 方法，检查四行页、末页、同页更新、跨页、seek、重复文字、换歌、社区时间／Unicode、未知／纯文本／纯音乐／clear／stop、主题切换。旧 533 项不改。
- 视觉：实际 SwiftUI View，四场景、800×600／1280×800／1920×1080、短拉丁／CJK／混排／长句／翻译／纯文本。比较 V2 与 V3 字面、层次和材质。
- 动态：采集 60Hz 附近的实际显示帧并记录实际采样时间；检查 0／50／100／150／220／300／500ms、完整页序列、同 cue、页切换、快速中断、gate 关闭、频段归零；截图用合成原创输入，明确不等于实机音频验证。
- 工程：每帧不测量文本、不重建播放器、不增加常驻后台时钟；静态持续停更。新增状态／类型必须有产品用途；有更短清楚的系统原生方案优先用它。
- 集成：冻结校验、完整回归、Standards 与 Spec 并行 review、双架构构建、安装内容一致性、串行原生切换／记忆／退出检查。未执行的实机条件如实记录。
