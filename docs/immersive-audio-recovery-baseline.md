# 音频启动竞态补充基线（协调者）

固定正式实现 `6dce422d059d69b1181d7e9f6be8ff965c841879`，2026-10-11，修复尚未开始。

真实诊断副本只加入有界状态日志，未改变判断：PID38941 generation1 创建设备期间收到 nil 随后又收到 P；成功后仍执行旧 nil，立刻销毁并重建；generation2 createTap 返回 noErr + tap0，下一步 format 返回 !obj 后永久 failed。系统 UI 确认 Likeit Desktop 的 System Audio Recording Only 为 on。本轮没有 PCM-gap 或自动退出日志，不能把先前所有退出都解释为同一问题。

补充驱动将未修改的生产 DesktopAudio.swift 和 ImmersiveCore.swift 与合成 HAL fixture 一起编译。通过信号量阻塞真实 start 路径中的 aggregate 创建来重放意图交错，并检查调用计数、失效句柄和迟到监听。驱动不读取音乐或音频；执行前通过 nm 拒绝任何未替换的 AudioObject/AudioDevice/AudioHardware 系统调用。它不证明真实设备或TCC行为。

16 项检查中7项红（P-nil-P、P-nil、P-stop-P、zero-tap、zero-device、nil-io、stale listener），明确错误有界和8项cleanup绿。首次typecheck纠正了fixture里不可用的SDK常量；首次nm核对发现remove-listener未被shadow，补齐escaping签名后才允许运行。这些是冻结前的测试夹具修正；没有改生产代码制造红灯。

该补充与原先冻结断言并存，不能通过放宽旧测试完成修复。修复由独立开发会话实现，协调者执行全部测试与真实路径。
