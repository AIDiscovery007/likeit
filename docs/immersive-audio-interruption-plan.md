# 音频权限误报与恢复修复

基线 db73d67511fb5f99e397687d7bcbda18b4717be9，协调者先冻结行为，再交给原 high 开发会话实施。原245项测试和全部冻结文件保持不变。

## 已有证据

- 用户截图是应用自定义统一失败文案，不是macOS拒绝授权通知。
- 2026-10-11 06:22:03 本机 Likeit Desktop PID95117 的CoreAudio日志：`AudioHardwareCreateProcessTap: Tap object not found: 3041 with timeout 1001`。该日志证明tap创建异常，不能证明TCC拒绝。
- 未修改的生产DesktopAudio与协调者的合成HAL一起执行：正常PCM后停流2.2秒，再持续送PCM和刷新意图，仍显示截图原文且无非零音频特征；路由重建的一次NotRunning错误同样永久锁存。重放执行前nm确认无真实HAL符号。
- 代码将所有非取消错误和超过2秒断流置为永久failed；reconcile不断重发统一权限提示。暂时断流不是权限判断依据。
- 当前ad-hoc签名DR为架构cdhash，本机无现成有效codesigning identity。Apple TN3127明确此身份不能可靠跨版本继承隐私授权：https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements 。该问题独立于上述运行中恢复故障。

## 最小闭环

1. A01/A04：断流保留会话，归零并等待恢复；错误保留具体阶段/OSStatus、未知不得冒充拒绝。永久HAL错误仍保持有界，不轮询申请权限。
2. A02/A03：小型桌面内重试入口，最新意图判断、失败状态复位和串行重新开始；成功隐藏按钮。保持原退出、不可见、暂停和迟到回调语义。协调者新测试使用DesktopAudio.retry()入口，现有output回调兼容；UI状态传递由开发者选择简单线程安全方式。
3. A05：构建脚本支持显式LIKEIT_DESKTOP_SIGNING_IDENTITY，以同一固定身份签framework/app，失败不降级；manifest记录实际DR。未配置默认ad-hoc兼容现有打包流程，构建输出和README说明授权风险。此轮不生成或导入证书、不改信任与TCC。
4. 协调者：运行旧/新测试、检查冻结hash、规范/需求双轨review；安装后真实验证音频状态、重试入口、退出。只有观察到真实PCM才能报告真实音频通过。跨版本授权保持需固定身份及两个真实构建的验证，未验证不得宣称“一劳永逸”。

## 复现与验收边界

新增21项直接编译生产DesktopAudio的检查，覆盖PCM间断恢复、无效tap/普通错误/路由错误的显式重试、正常/隐藏/退出时重试无副作用。首次复现驱动在冻结前修正了Swift输出指针和旧PCM观测窗口；没有改生产代码或旧测试。

UI按钮、日志字段、签名分支通过review及集成验证；模拟HAL不能证明真实硬件或TCC。原R04/R05“失败不因刷新自动重试”保留；新增的用户主动重试不改变该语义。
