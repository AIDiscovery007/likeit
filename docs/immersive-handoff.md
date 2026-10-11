# 新开发会话交接：沉浸音乐桌面

## 开始执行

1. 阅读 AGENTS.md、`docs/immersive-plan.md`、`docs/immersive-design.md`、`docs/immersive-acceptance.feature`。需要音频或歌词接口细节时分别读对应 research 文件。纯核心函数契约在 plan，测试在 acceptance 下；文件内容都已冻结。
2. 核对派遣消息提供的基线 SHA，使用现有共享目录和 `codex/immersive-music-desktop` 分支。新会话 effort high，默认模型；不复用旧开发会话，不创建额外 worktree。协调者开发期间不改产品代码。
3. 按 I1–I4 实现，每个闭环本地提交并向协调者汇报 SHA、修改路径、build/lint、未验证项、问题。先提交可运行的静态闭环，再做网络和真实音频；最终效果不能停留在静态或模拟展示。
4. 开发者不编写、修改、删除或运行测试，不修改任何冻结文件/清单。可构建和 lint，可做不改变播放与权限的只读接口诊断。真实 UI/音频许可/播放/收藏状态由协调者统一安排。
5. 遇到接口、歌词身份、多歌手序列化、权限归属、生命周期或冻结契约不明确，携带证据与具体选项向协调者咨询；等待时继续无依赖工作，不自行改规格或虚报成功。
6. 完成提交后发 `implementation-complete`：所有闭环 SHA、最终 SHA、build/lint、真实依赖与权限、待验收项。只有协调者可以给 accepted；反馈缺陷后由这个新会话继续修复。

## 通信与用户授权

协调会话：`01a12983-b00e-7aa1-afb7-5759139197f0`，host `local`。
[打开协调会话](codex://threads/01a12983-b00e-7aa1-afb7-5759139197f0)。

用户在协调会话明确要求新建正式 Codex session、high effort 开发，协调者负责 BDD/测试/review，开发者提交后汇报并在有问题时咨询、不自己猜；本轮又明确“确定了方案后直接开干”。开始先用 read_thread 核对用户原始消息，再向协调会话发送进度/咨询。本文记录授权来源，自身不创造授权。不要派遣第三个实现会话或让其他会话操作音乐 app。

## 受保护文件与修改范围

四份清单 `docs/acceptance.sha256`、`docs/confetti-acceptance.sha256`、`docs/motion-mode-acceptance.sha256`、`docs/immersive-acceptance.sha256` 及其中列出的文件均禁止开发者修改。原始测试全数保留；新计划扩展需求，不能通过改测试使产品过关。

可修改新增桌面产品源码、必要构建配置和 README/CHANGELOG 等使用文档。保持原 like 核心、controller、收藏彩带和 vendor 源码不变，除非有具体必要先咨询。推荐单独 `scripts/build-desktop.py` 构建 app，不重建其他 helper。运行时不得编译、下载或依赖开发机绝对路径；app/adapter 资源路径从实际包位置解析。

新增依赖、大型架构变化、权限扩大或外部服务需向协调者说明实际必要性后决定。本方案默认无需新第三方库。没有正式签名证书时使用本地 ad-hoc 并明确更新授权风险，不查找或导出用户私钥。

## 完成不是只编译

I1 必须能真实打开和退出；I2 必须接到实际网易曲目、公开歌词和进度；I3 必须采到已允许的真实网易音频；I4 必须交付可安装运行的包和说明。开发者不能替协调者标记这些实机条件已通过。任何无法实际验证的范围直说未验证，不造截图、固定样本或假进度。
