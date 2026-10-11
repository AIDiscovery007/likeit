# 迭代：收藏确认后的双侧彩带

起点：`19f39386390620d49b20b7aa42df1bac325ed2ab`。负责人仍为原协调与开发会话，开发 effort 为 high。旧计划、旧 BDD 和旧冻结清单保持原样；本文件是新需求的补充，不放宽旧收藏行为。

## 结果与选择

用户运行 like → 同曲的新收藏已由客户端确认 → 音乐会话完成清理、锁释放 → 原成功 HUD → 当前工作屏幕两侧向中央喷一轮彩带。彩带用于让用户感知这首歌已收进喜欢列表，不参与成功判定，不增加等待输入的步骤。

优先复用 Raycast 官方 `raycast://confetti`。协调者实际看到双侧朝内上方的纸片；也实际看到外部 URL 打开时的 Run Command 确认框。扩展内 `open("raycast://confetti")` 是否同样弹框尚未知，这必须先验证。不能把“URL 打开成功”当视觉或无干扰通过，不能设置 Always Run、猜跳确认参数或借用 Codex 自己的 confetti 工具。

原生备选为固定的 ConfettiSwiftUI 3.0.0（MIT，commit `9ae5bc2ce2149980884d4612321c3a266d6bf82c`）加一个非激活、鼠标穿透的透明 NSPanel。canvas-confetti 1.9.4（ISC）的 School Pride 是准确视觉参考，但需要额外 WebKit 容器，因此不作为默认依赖。研究证据和源码链接见 `confetti-research.md`。备选不是并行实现任务；内置路径不合格时向协调者报告，由协调者决定切换。

## 产品行为与边界

- 仅最终 `liked` 触发一次。`already-liked`、`unconfirmed`、`busy` 及所有错误/拒绝状态沿用原 HUD，不庆祝。会话 close 失败导致的最终状态必须先落实，不能根据中途成功提前发射。
- 新增 Raycast checkbox 偏好 `successConfetti`，默认 true。用户关闭后不读取动画策略或启动渲染。
- 发射前可靠读取 macOS Reduce Motion；只有明确 false 才允许。true、缺失、格式异常、读取失败均保留 HUD 并跳过。不得更改用户系统设置或假设 Raycast 已自动支持这一点。
- HUD 先呈现，动画启动失败/缺依赖/超时不能改写成功提示、重试收藏或重试动画。反馈阶段不能持有音乐锁。
- 动效无声音，一轮短暂双侧喷射后自动消失。原生备选建议约 1.5–2.5 秒，最晚 3 秒关闭自己的窗口并退出；Raycast 内置时长实际测量并记录，不能虚构可配置参数。
- 不抢焦点、不吞键鼠、不激活播放器、不切换 Space、不额外打开浏览器/确认框。连续请求不得无界叠加、排队或留下窗口；解释所用方案的实际去重/结束行为。
- 在当前工作屏幕展示。内置方案实测其屏幕选择；原生备选在启动时固定鼠标所在屏幕，没有匹配屏幕则保守跳过，不在所有屏幕重复发射。
- 保留旧音乐 controller、身份守卫、状态契约和锁。动画只接收显示请求，不读取 Cookie、不访问音乐 app，也不需要新的辅助功能/录屏/自动化授权。
- 如需原生读取 Reduce Motion，允许新增独立只读小 helper，使用 AppKit 官方属性，复用既有双架构预编译与摘要/签名流程；不要给音乐 controller 增添 GUI 生命周期。用户不编译、不下载运行时依赖。

## 最小闭环与决策门

| 闭环 | 开发者交付与本地提交 | reviewer 验证与完成条件 |
| --- | --- | --- |
| C0 冻结基线 | 由协调者先提交本计划、研究、新 BDD、新测试及红灯记录 | 旧 28 条保持通过；新契约在缺少实现时预期失败；记录基线 SHA |
| C1 内置可行性探针 | 提供与音乐完全隔离的最小 no-view 预览入口，只调用官方 open 固定 URL；提交代码、运行方法和 build/lint，不自行点动效 | 协调者在真实 Raycast 中预览，记录确认框、HUD、视觉、焦点、持续时间。预览命令只用于本闭环，最终生产清单不保留。若有阻塞，带证据咨询，不能自行放宽 C06 |
| C2 反馈决策 | 实现下方纯 TypeScript 反馈入口、偏好和可靠的 Reduce Motion 读取；先不改变收藏核心 | 协调者运行新旧冻结用例。可在 C1 等待决策时完成；必须检查正式入口将来调用同一受测路径 |
| C3 实际连接 | 按 C1 决策接入通过的 renderer；正式入口在原会话 finally 清理后反馈；落实有界启动与重叠/结束行为 | 预览可用且不碰音乐；真实 like 成功才发射，重复/关闭偏好/减少动态效果/失败不误发；检查前台输入、Space 和资源清理 |
| C4 交付与复核 | README、许可证/来源（有引入才需要）、构建与产物信息；移除开发预览入口；提交 implementation-complete | 固定提交 review，新旧冻结检查、build/lint、真实路径及未验证范围分别记录。发现问题在原开发会话修复，不能调整测试迎合实现 |

C1 首次预览只证明内置路径的基础行为；减少动态效果、并发和全屏等仍需 C3 单独验证。如需原生备选，开发者先提供最小包装方案和依赖摘要，协调者在新决策记录中批准后继续；本冻结契约不重写。

## 独立自动化接口

新增 `src/result-feedback.ts`，不导入 Raycast 或执行进程，使用 Node 24 可直接执行的 TypeScript：

```ts
type FeedbackStatus = Status | "busy";
type FeedbackPort = {
  showHUD(status: FeedbackStatus): Promise<void>;
  readReduceMotion(): Promise<boolean | undefined>;
  celebrate(): Promise<void>;
};
export function presentResult(
  status: FeedbackStatus,
  enabled: boolean,
  port: FeedbackPort,
): Promise<void>;
```

showHUD 收到原状态，正式 adapter 映射为现有文字。顺序为先 HUD，符合状态/开关才读 motion，仅 false 才发起 celebrate。motion 和 celebrate 的同步/异步异常在可选反馈边界内消化；不重发 HUD、不修改收藏结果。实际 motion/celebrate adapter 必须设有限的超时与清理；celebrate 表示一次启动尝试，不得无限等待粒子结束。旧音乐会话关闭由正式入口负责，reviewer 还会静态核对它确实调用本受测入口。

`node --test acceptance/confetti-feedback.test.mjs` 固化 18 个反馈行为用例；不是截图测试，也不能证明真实 Raycast、macOS 或粒子库行为。旧 `node --test acceptance/like-current-track.test.mjs` 仍必须运行。

## 实际验证范围

1. 预览与音乐完全隔离；左右两侧朝内喷射，短暂结束，无浏览器/确认框、无阻挡输入。
2. 用户指定的新样本：[Popular — The Weeknd / Playboi Carti / Madonna](https://music.163.com/song?id=2052348113)。公开标题已核对；实际写入前仍须确认当前正播放同曲、尚未喜欢，变化则停止。不得取消 Antisocial 的喜欢制造样本。
3. 首次确认喜欢一次彩带；再次调用无彩带；关闭开关无彩带；未知/失败/未确认无彩带。
4. 系统减少动态效果、策略读取失败、URL/渲染失败、启动超时；原成功文字和音乐结果保持。真实系统设置由用户操作，注入只能证明错误处理，不能冒充真实偏好体验。
5. 普通前台 app、另一个 app 全屏/Space、多屏，动画期间键盘输入/点击，连续启动及退出后窗口/进程清理。缺环境的项目明确未验证。
6. 旧收藏路径回归；无新增隐私授权、网络下载或用户编译步骤。

## 派遣与写入规则

继续 [原开发会话](codex://threads/01a12995-4d3b-7bf3-82da-c9181687b34b)，effort high。协调会话仍为 `01a12983-b00e-7aa1-afb7-5759139197f0`。用户本轮明确要求“让开发继续实现”，原有汇报/咨询授权持续有效。

开发者不写、改、删、运行任何测试；不改旧冻结文件、新 `confetti-acceptance.sha256` 所列文件及清单。build/lint、实现源码和使用文档可做。每闭环本地提交后报告 SHA、修改、证据、局限；不 push、不发布。遇到接口/依赖/权限/契约疑点先问协调者，不猜。开发者不执行真实收藏；可视预览和测试由协调者统一安排，不同时控制用户桌面。
