# 全屏与歌词动效 V2 review

源码 `8582d040c1a5dbdf020d50426345cd3fb2fc8b1e` 通过代码、冻结验收和离线真实视图检查，允许进入最终合并重建。安装后的键盘、持久化、退出和实机画面在集成后补充，不用离线输入冒充真实采集成功。

用户此次纠正已落实：玻璃音响铺满窗口，无 demo 外围底色/留白；真实歌词行淡入滑入并保留逐字高亮；四场景响应现有真实频段，音频失败不阻断可信歌词时钟。经典主题与原有来源、缓存、采集链路保留。

## 范围与冻结

- 固定验收基线：`2d98d5c45bdd27098da57c359c4e7c29477f30e7`，先于实现提交；V2 冻结 224 文件，最终摘要全部通过。
- 开发会话：[开发 Likeit 透明音响可选主题](codex://threads/01a12b1f-c9c0-7143-aed4-4cfd1a953507)，独立 `codex/transparent-speaker-development`，effort high。
- 产品闭环：`19c4f2b` 全屏与快捷键；`1cb1ad9` 真实歌词身份/时间/门控；`8582d04` 四场景响应与视觉修复。
- 产品仅修改 DesktopView、DesktopMain、DesktopSession 的窄呈现字段和使用说明。开发者未修改或运行测试，未改验收、计划、冻结清单，未覆盖用户安装。
- V1 既有冻结契约保持原样；补充契约明确记录了用户对固定 16:9 展示框与静态场景的纠正，不为实现修改旧断言。

## Standards

独立 standards review：0 项硬规则违规，0 项值得要求修改的代码异味。没有新依赖、权限、采集、业务会话或播放器时钟；旧三文件编译边界保留。两处很短的三频段门控没有为了抽象而增加间接层。

## Spec

独立 spec review：0 项未解决缺陷。真实 track/index/start 识别歌词行，同 cue 的逐字更新不重新入场；首次进入与关闭门控完整呈现；未知位置清除 cue/position。四场景时间相位均由真实频段幅度约束，归零静态，音频失败不关闭歌词时钟。

两轴均为 0 项未解决发现。它们不替代以下实际测试和视觉检查。

## 协调者验证

| 检查 | 结果与证据 |
| --- | --- |
| 旧实现红灯 | `baseline-red.tap`：858f715 缺少 cue/position/motion 接口。临时接口原型仅在 /tmp 验证 harness 可编译并执行 35 场景；随后删除，生产和断言未改 |
| 定向回归 | `lyrics-targeted.tap`：83/83，覆盖新增 35 场景、主题/路由及旧逐字高亮 |
| 完整回归 | `full-8582d04.tap`：533/533，0 fail/skip/cancel，60.9s；命令 `node --test --test-concurrency=2 acceptance/*.test.mjs` |
| 全屏布局 | `final-layout/`：四场景、800×600、1280×800、1920×1080，另含1000×700长文；玻璃贴边，透明中心、反光、木沿保留，长中英文/emoji/翻译可读；纯文本显示在滚动区 |
| 歌词动效可见 | `final-motion/line-020ms.png`、`line-150ms.png`、`line-600ms.png`：真实生产 View 随注入的可信位置从入场到稳定；主文字与翻译一起进入 |
| 动效中断 | `final-motion/interrupted-motion-off.png`：快速更换 cue 后关闭门控，最新行立即完整可读；与800ms后 `motion-off-stable.png` 全图像素一致 |
| 四场景响应 | `final-motion/*-rest/energy/zero.png`：青瓷光斑、条纹落日、夜航星光波纹、纸页三频段条形均发生可见变化；四场景归零后均与静态基态全图像素一致，见 `pixel-comparison.json` |
| 开发构建 | 开发者报告双架构 build/codesign/lipo、全原生与三文件 typecheck、TypeScript、ESLint、Prettier 通过；安装包由原主协调者合并后重建，不复用分支二进制 |

证据均在 `docs/review-evidence/transparent-speaker-v2/`。离线图的原创文本、播放位置和频段均标为 synthetic：证明生产 View 的呈现与门控行为，不证明用户机器的实机音频权限或采集结果。

## 发现与修复

| 发现 | 修复与复查 |
| --- | --- |
| 800×600 且有重试按钮时，右下扬声器与状态第一行贴边，影响可读性 | 8582d04 把右扬声器上移，`layout/small-800.png` 与 `final-layout/small-800.png` 对照确认有清楚间距 |
| 透明场景标签被挤成两行，顶部叠层拥挤 | 8582d04 隐藏玻璃内 picker 的视觉标签并保留 AX label，最终大小窗口均正常；AX 实机复查在安装后执行 |

## 集成后实机记录

待最终重建与安装完成后补充。剩余需实际确认：主题 Cmd+1/2、四场景 AX 选择、普通重开记忆、同一进程反复切换、Esc/Cmd+Q/按钮退出。未改系统 Reduce Motion、未授予新权限、未控制音乐播放；若实机采集条件不满足，明确标为未验证。
