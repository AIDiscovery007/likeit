# V3 review：透明歌词海报与分层律动

范围：`698c618` 之后的 V3 增量；设计与行为先于开发冻结于 `23c56c6`，连续性增量先于修复冻结于 `8d80e32`。高级专员在独立 `codex/transparent-speaker-polish` 分支实现，每个闭环本地提交；测试、验收和 review 由协调者负责。

## 设计与适配

原稿逐帧拆解见 [reference-analysis.md](review-evidence/transparent-speaker-v3/reference-analysis.md)，61 个 60Hz 数学采样见 reference-frames.json。这些是原 HTML 公式的采样，不是浏览器截图。原稿的关键是四行海报字面、快起缓收的入场、外圈与振膜的幅度差，以及慢背景与快能量的分工。

新实现恢复四行逐步累积的海报、Impact／重字重 CJK、220ms 淡入和 500ms 位移、320ms 可中断旧页淡退、1.012／1.06 的外圈／振膜尺度上限，以及四种背景各自的空间构图。歌词和频段仍来自原管线；零能量与 gate 关闭静止，没有 demo 假节拍。

原稿的大驱动单元与同一左边线会遮住真实长句。布局决策明确采用每行的可用横向区间，保留对角驱动单元和大字尺度，不让不透明外圈截断正文。纯文本也使用安全阅读列。经典主题没有重设计。

## Standards review

独立审查以 AGENTS.md、先验设计和冻结边界为准：首次产品审查 0 项标准违规、0 项可执行代码气味；`4865adc` 增量复审仍为 0 项。产品范围只有 DesktopView、DesktopSession 与使用说明，无依赖、图片资产、第二采集、播放器框架或测试改动。

## Spec review

首次最终审查发现 1 个 P2：250ms 墙钟容差可能把带 150ms 残差的邻接 seek 当作正常推进。先新增 21 个行为场景并记录预期红灯，再修复产品；不修改旧 571 项和 233 文件冻结。

`4865adc` 的 Spec 复审关闭该 P2，未发现新的需求回归。最终判定使用同一次真实位置计算提供的 position／单调采样时间／rate，删除 View 观察时间状态；相同正速率、有效采样间隔及 5ms 残差内才允许顺序入场。小幅 seek、变速、缺样本、同 cue 内中断均直接显示最新状态。源端没有独立 seek 事件，5ms 内微小变化无法可靠区分；没有声称无限精度。

## 验证与边界

协调者通过真实生产 Session 方法与 View.receive 执行 BDD。旧契约文件校验不变。开发者只构建与 lint，不写或运行测试。

视觉验收直接渲染生产 SwiftUI View，输入为原创合成歌词与三频段，使用隔离偏好，不操作音乐或音频采集。覆盖四场景、800×600／1280×800／1920×1080、长句／混排／Unicode、纯文本、未知状态、连续入场、跨页、跳转和 gate 中断。

离屏截图速度约 10–30fps，所有帧记录实际采样时间；不能由此宣称实机稳定 60fps。源曲线 60Hz 数学表与真实离屏帧是两类证据。零能量返回的像素等同静态初态，gate 中断后的前后帧相同，非零能量帧不同。该证据不等于实机音频捕获验证。

中间校准原帧保留在 `/Users/qiaochao/.codex/review-evidence/likeit-transparent-speaker-v3`，仓库只保存可复现渲染脚本、关键图和最终日志，避免提交重复大图。

## 最终源码验收结果

产品源码：`4865adc3f74f03f9f60c3011aca4b1bd5b004585`。相对 V2 只改变两个 Swift 文件与使用说明，402 行增加、145 行删除。

| 验证 | 结果 |
| --- | --- |
| 新连续性及相关 poster/motion 回归 | 96/96，15.50s |
| 全部 acceptance | **593/593**，64.19s，0 fail/skip/cancel |
| 冻结校验 | 原 233 文件与增量 6 项逐字节匹配 |
| Standards / Spec | 0 项；原 P2 已关闭 |
| 开发构建 | arm64/x86_64 与签名验证、三文件 Swift typecheck、TypeScript、完整 lint 通过 |
| 真实 View 离屏 | 56 张 PNG，四场景、三尺寸及异常状态完整；关键图保存在 accepted/ |
| 音频合成输入 | 四场景 rest==zero，pulse!=rest；中断后稳定帧完全相同 |

最终实际入场样本约 43/114/187/258/327/395/466/528/597/661ms；换页约 144/246/345/440/506/584/658ms。离屏渲染耗时包含 AppKit 截图，不能拿它推断屏幕合成帧率。基线和 V3 对比使用相同原创文本，before-after.png 的 V3 静态构图对应 badc47e，与最终源码的静态视觉相同。

复现渲染：

```sh
python3 docs/review-evidence/transparent-speaker-v3/prepare-sampled-render.py /tmp/likeit-v3-sampled-render.swift
xcrun swiftc native/ImmersiveCore.swift native/DesktopCommunityLyricsCore.swift native/DesktopView.swift /tmp/likeit-v3-sampled-render.swift -o /tmp/likeit-v3-sampled-render
/tmp/likeit-v3-sampled-render /tmp/likeit-v3-frames
node --test --test-concurrency=2 acceptance/*.test.mjs
```

原始 render-poster.swift 的 0.5→4.0 是 seek，必须立即呈现。单独保留的 render-sequential.swift 使用 3.9→4.0 检查顺序入场；未把 seek 的失败预期改成动画成功。sample 适配只为这份合成输入补上同速率采样时刻，没有修改产品或行为断言。最终全帧哈希、真实时间与像素比较见 accepted/ 下的 JSON。

源码验收通过；统一构建安装与原生操作检查在下一条集成记录中单独登记，不能由离屏结果代替。

## 主分支统一构建与安装

主协调者从 `698c618` 快进合入 `9c3f267`，确认 native、src、acceptance、scripts 和 package.json 与完成 593/593 回归的 `4865adc` 一致，引用该固定源码的回归记录，没有重复运行相同测试。32 份冻结清单的 780 条记录全部核验通过；旧清单及用户原始 HTML 未变。

从合并源码重新运行 `scripts/build-desktop.py` 构建 arm64/x86_64，保持既有 ad-hoc hardened runtime 签名。确认桌面进程不存在后执行 `npm run build` 安装。13 项源码和 10 项包文件摘要一致，安装 manifest 与仓库逐字节一致；已安装包通过 strict deep codesign 和双架构校验。完整摘要见 `review-evidence/transparent-speaker-v3/main-installation.json`。

安装过程没有启动桌面、控制音乐、修改签名身份或系统权限；安装后确认无桌面进程。UI 锁交回主题协调会话，实际原生操作与音频表现的验收边界由后续实机记录说明，本节不把安装成功记作实机通过。

## 原生操作验收

在重建安装 `db8e4b5c9c5f8f82545248a8303fcaf5df3289f3` 上通过 CUA 操作真实 app。检查前偏好为 glass/paper，桌面未运行。全屏纸页画面、四场景名称与选中 AX 状态均核对；Cmd+1/2 连续切换 10 次全部正确，切换前后 PID 均为 59751。鼠标主题选择、透明与经典各自退出重开记忆均正常。Esc、Cmd+Q、退出按钮之后分别确认进程消失。最后恢复 glass/paper，退出并释放 UI。详见 `review-evidence/transparent-speaker-v3/live-ui.json`。

当前没有可靠网易云播放来源，冷启动保持 mode off；实机界面如实显示未知来源及不采集音频。本次没有更改音乐播放、系统减少动态效果或权限，不能声称真实声卡律动或权限失败已实测。焦点恢复与屏幕持续 60fps 未独立测量。动态行为由真实 View 合成帧和冻结生产方法测试验证。源码与原生操作验收完成，这些边界保留在交付记录中。
