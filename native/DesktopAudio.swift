import AppKit
import CoreAudio
import AudioToolbox

private enum CaptureError: Error { case unavailable(OSStatus), format }

final class DesktopAudio {
    private let queue = DispatchQueue(label: "com.likeit.desktop.capture", qos: .userInitiated)
    private let ioQueue = DispatchQueue(label: "com.likeit.desktop.pcm", qos: .userInteractive)
    private let bufferLock = NSLock()
    private let buffer = UnsafeMutablePointer<Float>.allocate(capacity: 2048)
    private var cursor = 0
    private var filled = 0
    private var lastPCM = 0.0
    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var ioProc: AudioDeviceIOProcID?
    private var listeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var timer: DispatchSourceTimer?
    private var sampleRate = 0.0
    private var currentPID: pid_t?
    private var desiredPID: pid_t?
    private var failed = false
    private var stopped = false
    private var rebuilds = 0
    private var lastRebuild = 0.0
    private var smoothed = AudioFeatures(rms: 0, low: 0, mid: 0, high: 0)
    var output: ((AudioFeatures, String) -> Void)?

    init() { buffer.initialize(repeating: 0, count: 2048) }
    deinit { buffer.deinitialize(count: 2048); buffer.deallocate() }

    func update(pid: pid_t?, reason: String) {
        queue.async { [self] in
            guard !stopped else { return }
            desiredPID = pid
            if pid == currentPID && pid != nil { return }
            releaseCapture()
            if let pid, !failed { start(pid) }
            else { publish(.init(rms: 0, low: 0, mid: 0, high: 0), failed ? "实时律动不可用 · 请检查系统音频权限或输出设备，退出后重开" : reason) }
        }
    }

    func stop(completion: @escaping () -> Void) {
        queue.async { [self] in
            stopped = true; desiredPID = nil; releaseCapture()
            DispatchQueue.main.async(execute: completion)
        }
    }

    private func checked(_ status: OSStatus) throws { if status != noErr { throw CaptureError.unavailable(status) } }
    private func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }
    private func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, into value: inout T) throws {
        var property = address(selector)
        var size = UInt32(MemoryLayout<T>.size)
        try withUnsafeMutablePointer(to: &value) { pointer in
            try checked(AudioObjectGetPropertyData(object, &property, 0, nil, &size, pointer))
        }
    }

    private func start(_ pid: pid_t) {
        do {
            guard neteasePID() == pid else { throw CaptureError.format }
            var process = AudioObjectID(kAudioObjectUnknown)
            var qualifier = pid
            var property = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
            var size = UInt32(MemoryLayout<AudioObjectID>.size)
            try checked(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, UInt32(MemoryLayout<pid_t>.size), &qualifier, &size, &process))
            guard process != kAudioObjectUnknown else { throw CaptureError.format }
            var actualPID: pid_t = 0
            var bundle: CFString = "" as CFString
            try read(process, kAudioProcessPropertyPID, into: &actualPID)
            try read(process, kAudioProcessPropertyBundleID, into: &bundle)
            guard actualPID == pid, bundle as String == neteaseBundle else { throw CaptureError.format }
            let description = CATapDescription(stereoMixdownOfProcesses: [process])
            description.name = "Likeit NetEase visualization"
            description.isPrivate = true
            description.muteBehavior = .unmuted
            try checked(AudioHardwareCreateProcessTap(description, &tap))
            var format = AudioStreamBasicDescription()
            try read(tap, kAudioTapPropertyFormat, into: &format)
            guard format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                  format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0, format.mBitsPerChannel == 32,
                  format.mChannelsPerFrame > 0, format.mChannelsPerFrame <= 2, format.mSampleRate.isFinite, format.mSampleRate > 0 else { throw CaptureError.format }
            sampleRate = format.mSampleRate
            let composition: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Likeit Private Audio",
                kAudioAggregateDeviceUIDKey: "com.likeit.desktop." + UUID().uuidString,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceTapAutoStartKey: false,
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]]
            ]
            try checked(AudioHardwareCreateAggregateDevice(composition as CFDictionary, &device))
            try checked(AudioDeviceCreateIOProcIDWithBlock(&ioProc, device, ioQueue) { [weak self] _, input, _, _, _ in
                self?.receive(input)
            })
            currentPID = pid
            publish(.init(rms: 0, low: 0, mid: 0, high: 0), "等待网易云实时音频 · 如有系统音频授权提示，请由你选择")
            try checked(AudioDeviceStart(device, ioProc))
            for (object, selector) in [
                (AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice),
                (AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyServiceRestarted),
                (AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList),
                (process, kAudioProcessPropertyDevices),
                (tap, kAudioTapPropertyFormat),
                (device, kAudioDevicePropertyDeviceIsAlive)
            ] { try listen(object, selector) }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: 1.0 / 30, leeway: .milliseconds(3))
            timer.setEventHandler { [weak self] in self?.analyze() }
            self.timer = timer
            timer.resume()
            publish(.init(rms: 0, low: 0, mid: 0, high: 0), "等待网易云实时音频 · 首次使用请允许系统音频访问")
        } catch {
            failed = true
            releaseCapture()
            publish(.init(rms: 0, low: 0, mid: 0, high: 0), "实时律动不可用 · 系统音频访问或输出设备未就绪")
        }
    }

    // The callback only copies into fixed storage; contention drops a frame instead of blocking I/O.
    private func receive(_ input: UnsafePointer<AudioBufferList>) {
        guard bufferLock.try() else { return }
        defer { bufferLock.unlock() }
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard let first = buffers.first, first.mNumberChannels > 0, first.mData != nil else { return }
        let frames = min(8192, Int(first.mDataByteSize) / (4 * Int(first.mNumberChannels)))
        for frame in 0..<frames {
            var sum: Float = 0
            var channels = 0
            for audio in buffers {
                guard let data = audio.mData, audio.mNumberChannels > 0 else { continue }
                let count = Int(audio.mNumberChannels)
                guard (frame + 1) * count * 4 <= audio.mDataByteSize else { continue }
                let values = data.assumingMemoryBound(to: Float.self)
                for channel in 0..<count { sum += values[frame * count + channel] }
                channels += count
            }
            guard channels > 0 else { continue }
            buffer[cursor] = sum / Float(channels)
            cursor = (cursor + 1) % 2048
            filled = min(2048, filled + 1)
        }
        if frames > 0 { lastPCM = ProcessInfo.processInfo.systemUptime }
    }

    private func analyze() {
        guard let pid = currentPID, neteasePID() == pid else { releaseCapture(); publish(.init(rms: 0, low: 0, mid: 0, high: 0), "网易云来源已变化"); return }
        let now = ProcessInfo.processInfo.systemUptime
        guard bufferLock.try() else { return }
        let receivedPCM = lastPCM > 0
        let age = now - lastPCM
        let samples = filled == 2048 && age < 0.15 ? (0..<2048).map { buffer[(cursor + $0) % 2048] } : []
        bufferLock.unlock()
        if !receivedPCM {
            publish(.init(rms: 0, low: 0, mid: 0, high: 0), "等待网易云音频 · 可检查系统音频权限或直接退出")
            return
        }
        if age > 2 {
            failed = true
            releaseCapture()
            publish(.init(rms: 0, low: 0, mid: 0, high: 0), "未收到音频 · 可能未授权、静音或设备不可用；退出后可重试")
            return
        }
        let value = analyzeAudio(samples: samples, sampleRate: sampleRate)
        func smooth(_ old: Double, _ next: Double) -> Double { next == 0 || age >= 0.15 ? 0 : old + (next - old) * (next > old ? 0.7 : 0.3) }
        smoothed = .init(rms: smooth(smoothed.rms, value.rms), low: smooth(smoothed.low, value.low), mid: smooth(smoothed.mid, value.mid), high: smooth(smoothed.high, value.high))
        publish(smoothed, value.rms > 0.00001 ? "网易云实时音频律动" : "音频安静 · 保持静态")
    }

    private func listen(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) throws {
        var property = address(selector)
        let callback: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.routeChanged() }
        try checked(AudioObjectAddPropertyListenerBlock(object, &property, queue, callback))
        listeners.append((object, property, callback))
    }

    private func routeChanged() {
        guard currentPID != nil else { return }
        let now = ProcessInfo.processInfo.systemUptime
        // At most one reconstruction per second; repeated failure stays static until a fresh launch.
        guard now - lastRebuild > 1 else { return }
        lastRebuild = now
        rebuilds += 1
        if rebuilds > 3 { failed = true }
        releaseCapture()
        publish(.init(rms: 0, low: 0, mid: 0, high: 0), "音频设备变化 · 正在重新核对")
        if let pid = desiredPID, !failed, !stopped { start(pid) }
    }

    private func releaseCapture() {
        timer?.cancel(); timer = nil
        if device != kAudioObjectUnknown, let ioProc {
            AudioDeviceStop(device, ioProc)
            AudioDeviceDestroyIOProcID(device, ioProc)
        }
        ioProc = nil
        for (object, var property, callback) in listeners { AudioObjectRemovePropertyListenerBlock(object, &property, queue, callback) }
        listeners.removeAll()
        if device != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(device); device = AudioObjectID(kAudioObjectUnknown) }
        if tap != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tap); tap = AudioObjectID(kAudioObjectUnknown) }
        currentPID = nil
        bufferLock.lock()
        cursor = 0; filled = 0; lastPCM = 0
        buffer.update(repeating: 0, count: 2048)
        bufferLock.unlock()
        smoothed = .init(rms: 0, low: 0, mid: 0, high: 0)
    }

    private func publish(_ features: AudioFeatures, _ message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Main only consumes immutable features; all HAL state stays on capture queue.
            self.output?(features, message)
        }
    }
}
