import AppKit
import CoreAudio
import AudioToolbox
import os

private enum CaptureError: Error { case unavailable(String, OSStatus), invalid(String), cancelled }
private let audioLog = Logger(subsystem: "com.likeit.desktop", category: "audio")

final class DesktopAudio {
    private let queue = DispatchQueue(label: "com.likeit.desktop.capture", qos: .userInitiated)
    private let ioQueue = DispatchQueue(label: "com.likeit.desktop.pcm", qos: .userInteractive)
    private let bufferLock = NSLock()
    // Shared intent and publication epoch; never hold this lock across HAL calls.
    private let intentLock = NSLock()
    private var desiredPID: pid_t?
    private var stopped = false
    private var intentReason = ""
    private var intentRevision: UInt64 = 0
    private var reconcileQueued = false
    private var captureEpoch: UInt64 = 0
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
    private var failed = false
    private var failureMessage = ""
    private var lastRebuild = 0.0
    private var smoothed = AudioFeatures(rms: 0, low: 0, mid: 0, high: 0)
    var output: ((AudioFeatures, String) -> Void)?

    init() { buffer.initialize(repeating: 0, count: 2048) }
    deinit { buffer.deinitialize(count: 2048); buffer.deallocate() }

    // Record intent before dispatch: a blocking HAL call must not turn old UI events
    // into a stop/start sequence after the UI has already returned to the same PID.
    func update(pid: pid_t?, reason: String) {
        intentLock.lock()
        guard !stopped else { intentLock.unlock(); return }
        desiredPID = pid
        intentReason = reason
        intentRevision &+= 1
        let enqueue = !reconcileQueued
        reconcileQueued = true
        intentLock.unlock()
        if enqueue { queue.async { [self] in reconcile() } }
    }

    func stop(completion: @escaping () -> Void) {
        intentLock.lock()
        stopped = true
        desiredPID = nil
        intentRevision &+= 1
        intentLock.unlock()
        queue.async { [self] in
            releaseCapture()
            DispatchQueue.main.async(execute: completion)
        }
    }

    private func intent() -> (pid: pid_t?, reason: String, revision: UInt64, stopped: Bool, epoch: UInt64) {
        intentLock.lock(); defer { intentLock.unlock() }
        return (desiredPID, intentReason, intentRevision, stopped, captureEpoch)
    }

    private func reconcile() {
        while true {
            let request = intent()
            if !request.stopped {
                if request.pid != currentPID {
                    releaseCapture()
                    if let pid = request.pid, !failed { start(pid) }
                }
                if request.pid == nil || failed {
                    publish(.init(rms: 0, low: 0, mid: 0, high: 0), failed ? failureMessage : request.reason)
                }
            }
            intentLock.lock()
            if stopped || request.revision == intentRevision {
                reconcileQueued = false
                intentLock.unlock()
                return
            }
            intentLock.unlock()
        }
    }

    private func checkIntent(_ pid: pid_t) throws {
        let request = intent()
        guard !request.stopped, request.pid == pid else { throw CaptureError.cancelled }
    }

    private func isCurrent(_ epoch: UInt64) -> Bool {
        intentLock.lock(); defer { intentLock.unlock() }
        return !stopped && captureEpoch == epoch
    }

    private func checked(_ status: OSStatus, stage: String) throws { if status != noErr { throw CaptureError.unavailable(stage, status) } }
    private func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }
    private func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, stage: String, into value: inout T) throws {
        var property = address(selector)
        var size = UInt32(MemoryLayout<T>.size)
        try withUnsafeMutablePointer(to: &value) { pointer in
            try checked(AudioObjectGetPropertyData(object, &property, 0, nil, &size, pointer), stage: stage)
        }
    }

    private func start(_ pid: pid_t) {
        do {
            try checkIntent(pid)
            guard neteasePID() == pid else { throw CaptureError.invalid("verify-source") }
            var process = AudioObjectID(kAudioObjectUnknown)
            var qualifier = pid
            var property = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
            var size = UInt32(MemoryLayout<AudioObjectID>.size)
            try checked(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, UInt32(MemoryLayout<pid_t>.size), &qualifier, &size, &process), stage: "resolve-process")
            try checkIntent(pid)
            guard process != kAudioObjectUnknown else { throw CaptureError.invalid("resolve-process-handle") }
            var actualPID: pid_t = 0
            var bundle: CFString = "" as CFString
            try read(process, kAudioProcessPropertyPID, stage: "read-process-pid", into: &actualPID)
            try checkIntent(pid)
            try read(process, kAudioProcessPropertyBundleID, stage: "read-process-bundle", into: &bundle)
            try checkIntent(pid)
            guard actualPID == pid, bundle as String == neteaseBundle else { throw CaptureError.invalid("verify-process-identity") }
            let description = CATapDescription(stereoMixdownOfProcesses: [process])
            description.name = "Likeit NetEase visualization"
            description.isPrivate = true
            description.muteBehavior = .unmuted
            try checked(AudioHardwareCreateProcessTap(description, &tap), stage: "create-tap")
            try checkIntent(pid)
            guard tap != kAudioObjectUnknown else { throw CaptureError.invalid("create-tap-handle") }
            var format = AudioStreamBasicDescription()
            try read(tap, kAudioTapPropertyFormat, stage: "read-tap-format", into: &format)
            try checkIntent(pid)
            guard format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                  format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0, format.mBitsPerChannel == 32,
                  format.mChannelsPerFrame > 0, format.mChannelsPerFrame <= 2, format.mSampleRate.isFinite, format.mSampleRate > 0,
                  format.mBytesPerFrame == (format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0 ? 4 : 4 * format.mChannelsPerFrame) else { throw CaptureError.invalid("validate-pcm-format") }
            sampleRate = format.mSampleRate
            let composition: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Likeit Private Audio",
                kAudioAggregateDeviceUIDKey: "com.likeit.desktop." + UUID().uuidString,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceTapAutoStartKey: false,
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]]
            ]
            try checked(AudioHardwareCreateAggregateDevice(composition as CFDictionary, &device), stage: "create-aggregate")
            try checkIntent(pid)
            guard device != kAudioObjectUnknown else { throw CaptureError.invalid("create-aggregate-handle") }
            try checked(AudioDeviceCreateIOProcIDWithBlock(&ioProc, device, ioQueue) { [weak self] _, input, _, _, _ in
                self?.receive(input)
            }, stage: "create-io-proc")
            try checkIntent(pid)
            guard ioProc != nil else { throw CaptureError.invalid("create-io-proc-handle") }
            currentPID = pid
            publish(.init(rms: 0, low: 0, mid: 0, high: 0), "等待网易云实时音频 · 如有系统音频授权提示，请由你选择")
            try checked(AudioDeviceStart(device, ioProc), stage: "start-device")
            try checkIntent(pid)
            for (object, selector) in [
                (AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice),
                (AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyServiceRestarted),
                (process, kAudioProcessPropertyDevices),
                (tap, kAudioTapPropertyFormat),
                (device, kAudioDevicePropertyDeviceIsAlive)
            ] {
                try listen(object, selector)
                try checkIntent(pid)
            }
            let epoch = intent().epoch
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: 1.0 / 30, leeway: .milliseconds(3))
            timer.setEventHandler { [weak self] in
                guard let self, self.isCurrent(epoch) else { return }
                self.analyze()
            }
            self.timer = timer
            timer.resume()
            try checkIntent(pid)
            publish(.init(rms: 0, low: 0, mid: 0, high: 0), "等待网易云实时音频 · 首次使用请允许系统音频访问")
        } catch CaptureError.cancelled {
            releaseCapture()
        } catch {
            failed = true
            failureMessage = "音频启动失败 · 可重试音频"
            switch error {
            case CaptureError.unavailable(let stage, let status):
                audioLog.error("Capture failed: stage=\(stage, privacy: .public) OSStatus=\(status, privacy: .public)")
            case CaptureError.invalid(let stage):
                audioLog.error("Capture failed: stage=\(stage, privacy: .public) reason=invalid-result")
            default: audioLog.error("Capture failed: stage=start reason=unexpected-error")
            }
            releaseCapture()
            publish(.init(rms: 0, low: 0, mid: 0, high: 0), failureMessage)
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
            publish(.init(rms: 0, low: 0, mid: 0, high: 0), "等待网易云实时音频")
            return
        }
        if age > 2 {
            smoothed = .init(rms: 0, low: 0, mid: 0, high: 0)
            publish(smoothed, "音频暂时中断 · 等待恢复")
            return
        }
        let value = analyzeAudio(samples: samples, sampleRate: sampleRate)
        func smooth(_ old: Double, _ next: Double) -> Double { next == 0 || age >= 0.15 ? 0 : old + (next - old) * (next > old ? 0.7 : 0.3) }
        smoothed = .init(rms: smooth(smoothed.rms, value.rms), low: smooth(smoothed.low, value.low), mid: smooth(smoothed.mid, value.mid), high: smooth(smoothed.high, value.high))
        publish(smoothed, value.rms > 0.00001 ? "网易云实时音频律动" : "音频安静 · 保持静态")
    }

    private func listen(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) throws {
        var property = address(selector)
        let epoch = intent().epoch
        let callback: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, self.isCurrent(epoch) else { return }
            self.routeChanged()
        }
        try checked(AudioObjectAddPropertyListenerBlock(object, &property, queue, callback), stage: "listen-\(selector)")
        listeners.append((object, property, callback))
    }

    private func routeChanged() {
        guard currentPID != nil else { return }
        let now = ProcessInfo.processInfo.systemUptime
        // At most one reconstruction per second. start() latches an actual failure;
        // successful route changes never exhaust a lifetime attempt budget.
        guard now - lastRebuild > 1 else { return }
        lastRebuild = now
        releaseCapture()
        publish(.init(rms: 0, low: 0, mid: 0, high: 0), "音频设备变化 · 正在重新核对")
        let request = intent()
        if let pid = request.pid, !failed, !request.stopped { start(pid) }
        else { publish(.init(rms: 0, low: 0, mid: 0, high: 0), "音频设备不稳定 · 保持静态，退出后可重试") }
    }

    private func releaseCapture() {
        // Invalidate callbacks before HAL teardown can enqueue late notifications.
        intentLock.lock()
        captureEpoch &+= 1
        intentLock.unlock()
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
        let epoch = intent().epoch
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isCurrent(epoch) else { return }
            // Main only consumes immutable features; all HAL state stays on capture queue.
            self.output?(features, message)
        }
    }
}
