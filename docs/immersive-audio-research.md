# 沉浸音乐桌面：真实音频采集研究

日期：2026-10-11。范围：仅本机网易云、公开 macOS 音频 API、只读 SDK/官方样例检查与编译探针；未创建 tap/aggregate device，未启动采集、录音、权限请求或改变 app/系统状态。

## 推荐决策

- 使用 **macOS 14.2+ Core Audio process tap**，只包含已核实属于 `com.netease.163music` 的音频进程；`.unmuted`、private tap + private aggregate device，PCM 仅在内存分析，不落盘、不发送网络、不监听麦克风。
- 沉浸窗口与采集同属一个有固定 bundle ID、原生 Mach-O 主程序和 Info.plist 的 **Likeit Music Desktop.app**。Raycast 通过正常 app 启动机制启动它；不是继续把裸命令行 confetti helper 扩成长驻播放器。这是权限归属清晰的架构建议，不是 Apple 宣称 process taps 必须使用 `.app`。
- 第一版做真实音量包络和低/中/高频能量驱动的律动；瞬态峰值可作为“重音”效果，**不宣称精准 BPM/音乐学节拍识别**。歌词时间轴独立取播放器进度，不能由频谱推算歌词。
- 首版不实现 ScreenCaptureKit 自动后备；授权拒绝、未知来源或流失败时保留可退出的安静桌面，明确显示“实时律动不可用”。不得悄悄改为全系统混音、麦克风或随机跳动。

## 两个公开方案

| 问题 | Core Audio process taps | ScreenCaptureKit |
| --- | --- | --- |
| 最低版本 | `AudioHardwareCreateProcessTap` / destroy：14.2；类本身更早出现不代表可在旧系统创建 tap。[A][S1] | Framework 12.3；系统音频输出与 `capturesAudio`：13.0。[S3] |
| 限定来源 | `CATapDescription(stereoMixdownOfProcesses:)` 接受 **AudioObjectID，不是 PID**；包含列表隔离其他进程。避免 global/exclusive 初始化。[S2] | `SCContentFilter` 可以包含指定 `SCRunningApplication`；Apple 明确音频只能按 app 过滤，不能按窗口。[B][S3] |
| 权限 | Info.plist 必须含 `NSAudioCaptureUsageDescription`；首次启动含 tap 的 aggregate I/O 时系统请求系统音频录制权限。[A][C] | Apple WWDC 明确视频/音频采集需要同意，并记录在 Screen Recording 隐私设置；当前系统文案需实机核验。[B] |
| 画面与隐私 | 本身只读音频，无需屏幕像素。`.unmuted` 保持原播放器送往硬件。[S2] | 可只添加 `.audio` 输出而不处理屏幕帧，但 API 与内容过滤仍围绕显示器/窗口，不能据此宣称无需屏幕录制授权。[B] |
| 维护成本 | HAL 对象/IOProc/格式/设备变化需自行管理；无需虚拟声卡驱动。[A][S4] | CMSampleBuffer 回调、更新 filter/config、stopCapture 较统一；增加第二套授权与生命周期实现。[B] |
| 适用结论 | 本机与新增沉浸式功能首选。 | 若未来必须支持 macOS 13–14.1，再单独立项和验收；不能绕过用户拒绝第一种采集的选择。 |

## 本机与 SDK 证据

- SDK：`/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk`；Swift 6.2.1，目标本机 arm64 macOS 26。只读探针在 `/tmp/likeit-audio-research-20261011/read-process.swift`。
- 实际查询 `NSRunningApplication` + `kAudioHardwarePropertyTranslatePIDToProcessObject`：网易云 PID **17055** → AudioObjectID **127**，OSStatus 均为 0；当时 `kAudioProcessPropertyIsRunningOutput=0`。这仅证明对象映射可读，不证明正在播放、可采集或已授权，也不能持久化这些数字。
- 编译探针 `tap-compile.swift` 仅含未调用函数，`swiftc -parse-as-library -emit-object -target {arm64,x86_64}-apple-macos14.2` 均成功，未执行创建 tap。两架构编译成功不代替 Intel 或 14.2 实机验收。
- Swift 最小已编译接口形状：`let d = CATapDescription(stereoMixdownOfProcesses: [processObjectID]); d.isPrivate = true; d.muteBehavior = .unmuted; var tap = AudioObjectID(kAudioObjectUnknown); let status = AudioHardwareCreateProcessTap(d, &tap)`；只在 status 成功且 tap 有效时取得格式/建 aggregate，清理调用 `AudioHardwareDestroyProcessTap(tap)`。这些语句在探针中均未运行。
- [S1] `.../CoreAudio.framework/Versions/A/Headers/AudioHardwareTapping.h:44` / `:54`：create/destroy 14.2 availability。
- [S2] `.../CoreAudio.framework/Versions/A/Headers/CATapDescription.h:20`（unmuted），`:49`（包含进程），`:125`（对象 ID），`:131` / `:162`（bundleIDs / processRestoreEnabled 仅 26.0），`:155`（private），`:175`（可选指定设备）。基础实现不依赖 26.0 特性。
- [S3] `.../ScreenCaptureKit.framework/Versions/A/Headers/SCStream.h:30` / `:295`（音频 13.0），`:165`（包含 app），`:300` / `:305`（采样率/通道），`:360`（15.0 才增加独立麦克风选项）。
- [S4] `.../CoreAudio.framework/Versions/A/Headers/AudioHardware.h:586`（进程列表），`:589`（PID→对象，找不到可能成功返回 unknown），`:1953`（PID/bundle/devices/running），`:2018`（tap 的实际格式）。所有 `...` 均以上述 SDK 的 `System/Library/Frameworks` 为根。

## 权限、打包与签名

- 官方 [AudioTapSample 下载][D] 的 `AudioTapSample/Info.plist:5` 有音频用途说明；`.entitlements:5`–`:12` 含 App Sandbox、audio-input、音乐目录和用户文件读写；`project.pbxproj:362`–`:370` 使用 Mac Developer 自动签名 + hardened runtime。
- 该样例还负责写音乐文件；Likeit **不复制音乐目录或文件读写 entitlement**。Hardened runtime 的 Core Audio 输入访问使用 `com.apple.security.device.audio-input`，它不能代替系统音频同意；该 entitlement 名称也不等于产品会调用麦克风。[E]
- 固定 native bundle/安装路径/签名身份；本地 ad-hoc 可用于开发构建，但不能承诺升级后授权保留。Apple DTS 说明 TCC 依赖 responsible code 和稳定签名，native 主程序应为 Mach-O；ad-hoc 更新可能反复请求权限。[F]
- `.app` 应用经 Raycast 真正启动后的权限归属仍需最早实测：系统提示应能识别 Likeit 音乐桌面，不能假定 Raycast/Codex/Terminal 的已有授权自动有效。不要修改宿主 Info.plist、TCC 数据库或借私有 TCC API 静默授权。
- 本轮没有找到可为 process tap 可靠区分“尚未询问/拒绝/已授权”的公开预检接口。设计以启动结果和实际 PCM 到达为依据；零样本不应直接定性为拒绝，也可能是暂停、静音、设备或音源限制。
- 首次权限应在用户主动进入沉浸模式后请求；只搜索 Likeit、打开设置或收藏歌曲不得触发。拒绝/等待期间保留 Esc 与退出按钮，授权后不自动修改系统输出设备。

## 运行与清理

- 启动：重新核实 NetEase bundle/PID → 转换音频对象 → 建包含 tap → 读 `kAudioTapPropertyFormat` → 建 private aggregate → 安装 I/O → 后台队列 start。不得只用曲名、前台 app 或静态 PID 选择音频。
- IOProc 只做有界拷贝/计算，不分配大对象、不访问 UI/网络/文件、不阻塞锁；固定容量缓冲与丢弃旧帧，分析队列输出最新 RMS/频段值，UI 30–60 Hz 读取快照。频谱对象/缓冲预分配。
- 正常退出、窗口关闭、来源消失、权限撤回或采集致命失败走同一幂等音频释放：先停 I/O → destroy IOProc → 移除 listeners → destroy aggregate → destroy tap → 清空 PCM；采集失败保留安静桌面，用户退出再关闭窗口/结束 helper。不可留下常驻监听、虚拟输出选择或音频文件。
- 官方样例 `AudioRecorder.mm:204`–`:248` 展示 start 失败清理、stop/destroy IOProc、设备/子设备/tap-list listeners；`AudioTap.swift:79` / `AggregateDevice.swift:69` 有对应 listener 移除。[D]
- **注意 SDK 的 `kAudioAggregateDeviceTapAutoStartKey`（AudioHardware.h:1635）会令 start 等待被 tap 的 app 首次有音频。** 不在 UI 主线程等待它；暂停、无流时必须能立即退出，退出不能卡在“等音乐开始”。
- 监听 AudioObject 进程列表/来源 PID、硬件服务重启、实际设备列表与格式变化；路由变化先归零旧能量，停止旧资源后有限重建，禁止同时活跃两套 tap 或无界重试。来源无法重新核实就降级，不扩大采集集合。

## 输出设备、延迟与诚实边界

- 进程立体声 mixdown 不固定具体 deviceUID；原播放路径仍由网易云/系统负责，理论上无需用户另选虚拟声卡。扬声器、有线/USB、蓝牙耳机的连续采集与热切换仍是实机验收项，不能由 API 签名推出全部兼容。[S2]
- 蓝牙扬声器/耳机存在硬件缓冲；tap 的数字音频到达时间不等于人耳听到时间。不要承诺零延迟/自动精准抵消蓝牙延迟，也不要为校准改变设备设置。
- 建议分析 FFT 2048、hop 512（48 kHz 时窗口约 42.7 ms、步长 10.7 ms），Hann 窗 + RMS 与频段能量 + attack/release 平滑；先以 **采样到视觉 ≤150 ms** 为工程目标，由 reviewer 测量，不是 Apple 的延迟保证。[G]
- 静音、暂停、流超时令真实能量归零并平滑回到静态构图；可有独立低速环境渐变，但不得标作音乐驱动。其他 app 单独出声时 NetEase 频段不得响应。
- “节拍”若只用频谱通量/低频瞬态阈值，本质是 onset/能量变化估计；古典/人声/弱拍、压缩音频和切歌会误检。首版不输出 BPM 数字或拍点保证，禁止定时随机脉冲冒充输入。
- 不在本轮声称 CPU/GPU/内存、连续播放稳定性、DRM 内容、耳机/蓝牙、旧系统或真实拒绝/撤回权限已通过。必须测真实音源；静态 SDK 和编译探针只能解除接口可用性疑问。

## 建议固化的 BDD 与主会话决策

- 自动化：给确定的静音/正弦/脉冲 PCM，验证 finite、归一化、频段归属、采样率变化、重置与 stale timeout；不能仅断言随机数变化或实现内部调用次数。
- 集成：仅网易云响/仅其他 app 响/两者都响；暂停与换歌；第一次允许/拒绝/撤回；进程重启；输出设备切换；重复进入；Esc/按钮退出后回调停止、aggregate/tap 归零且音乐继续原状态。
- 核心阻塞门：最早闭环验证**正式打包 helper 经 Raycast 启动后的权限归属和真实 PCM**；失败先咨询，不用纯展示动画绕过。
- 建议主会话确认：新功能最低 14.2（收藏旧路径不提高门槛）；独立 app bundle；首版无 SCK fallback；RMS/频段律动而非 BPM 保证；失败显示安静桌面并保留歌词/退出。

## 官方来源

[A]: https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps
[B]: https://developer.apple.com/videos/play/wwdc2022/10156/
[C]: https://developer.apple.com/documentation/bundleresources/information-property-list/nsaudiocaptureusagedescription
[D]: https://docs-assets.developer.apple.com/published/02fe64305fe7/CapturingSystemAudioWithCoreAudioTaps.zip
[E]: https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.audio-input
[F]: https://developer.apple.com/forums/thread/678819
[G]: https://developer.apple.com/documentation/accelerate/finding-the-component-frequencies-in-a-composite-sine-wave
