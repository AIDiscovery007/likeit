# 独立动效配置验收记录

2026-10-11。协调者编写；开发者不修改。用户明确选择的三态设置已实现、review 并注册到本机 Raycast。旧彩带整体视觉与真实收藏联动的待验项仍保留。

## 固定版本

- 预先冻结基线：`a894b093ac3204b684fa528f7527f59248cd0c6a`。
- 实现与隔离预览：`8bc28ae20ce70ca01f8925b847ebfe2b5b44a8f9`。
- 最终生产命令：`b2abadff021d3562c11cfc524e548c2806df7e10`。

最终提交只移除预览命令/源码并更新说明，正式实现和产物与预览提交完全相同；已独立核对。未 push 或发布。

## Standards review

独立 reviewer 未发现可行动问题。16 项冻结资料、11 项产物及源码摘要匹配，helper 签名通过。无新依赖、权限或音乐操作；锁、单轮和期限没有放宽。

## Spec review

独立 reviewer 未发现可行动问题。正式偏好只接受精确 system/always，其他值或读取失败关闭；boolean 兼容仅保留在旧反馈接口。always 贯穿两次原生发射前检查与通知处理，system 保留默认与系统策略。仅一个用户配置项，生产预览已清理。

## 协调者独立验证

固定归档 `/tmp/likeit-motion-modes.ZWeMoQ`：

- 新 22 条加旧 46 条，68/68 冻结用例通过；三份冻结清单共 16 项均一致。没有修改冻结断言或实现来掩盖失败。
- 18 个正式入口边界探针通过：真实入口/核心/反馈，模拟外部端口，覆盖三态、系统读取失败、无效/缺失偏好、旧 boolean 不能作为生产选项、会话清理失败等；检查模式精确传入 renderer、HUD 顺序和不误庆祝。
- 8 个 TS adapter 参数探针通过：默认/system/always 精确传参，off/无效值不创建 support 目录或启动子进程。
- 14 项真实原生检查通过：默认及显式 system 跳过当前 Reduce Motion、无效/多余参数、路径/符号链接/非普通文件守卫、always 也遵守已占用锁、退出后固定 inode 锁可重用。首个直接执行的缺参数进程约 1367 ms，其他约 5–11 ms；未扩大产品 1 秒启动等待，启动超时仍跳过可选反馈。该启动延迟不冒充动画时长。

临时证据为该归档的 `review-entry.mjs` / `review-entry-results.json`、`review-adapter.mjs` / `review-adapter-results.json`、`review-native.py` / `review-native-results.json`。

## 真实 Raycast 与窗口证据

协调者从隔离命令显式选择 always、system、off；三次模式均看到“Likeit 动效预览（不操作音乐）”HUD。预览不读写音乐、不修改持久配置或系统设置。

另用只读 AppKit/CoreGraphics 观察器连续采样窗口元数据及前台应用，不生成输入、不控制窗口：

- always：系统 Reduce Motion 仍为 true；实际检测到 `likeit-confetti` 的 1800×1169 屏幕窗口，63 个样本，首次至末次可见样本间约 2.13 秒；观察期前台保持 `com.openai.codex`，helper 未成为前台，窗口随后消失。
- system / off：各 12 秒观察期内该窗口样本数为 0，系统偏好仍为 true。
- 观察器与结果：`review-window-monitor.swift`、`review-window-always.json`、`review-window-system.json`、`review-window-off.json`。

桌面工具的应用库存没有列出短命 helper，因此未捕获粒子像素；只读窗口证据不能代替双侧方向、透明度、键鼠穿透、Space/全屏、多屏或显示期策略变更测试。一次追加 always 预览仍只捕获 Raycast HUD；没有以此宣称完整视觉验收。

随后注册最终固定归档 `/tmp/likeit-motion-final.SzGAmK`，仅编译 `src/likeit.ts`。实际打开 Raycast Settings → Likeit：唯一“收藏成功动效”项默认显示“跟随系统”，打开后可见“跟随系统／始终播放／关闭”三项；旧 checkbox 与预览命令均不存在。没有替用户选择持久模式，设置页留给用户。开发 watcher 已停止，检查时无彩带 helper 残留。

这完成了独立配置本身与模式路由验证。上一轮记录中的真实新收藏联动、粒子视觉及更广桌面兼容性仍待验收；本轮未操作用户的 Popular、Antisocial 或任何其他音乐。
