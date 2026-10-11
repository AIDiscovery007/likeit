import AppKit
import CoreAudio
import AudioToolbox

// Coordinator-owned HAL fixtures. These symbols shadow imported C APIs in this
// test module, while DesktopAudio.swift is compiled unchanged from production.
let neteaseBundle = "com.netease.163music"
func neteasePID() -> pid_t? { 77 }
struct Listener { let queue: DispatchQueue?; let block: AudioObjectPropertyListenerBlock; let address: AudioObjectPropertyAddress }
final class HAL {
    static let shared = HAL()
    let lock = NSLock()
    var counts: [String: Int] = [:]
    var listeners: [Listener] = []
    var mode = "normal"
    var input: AudioDeviceIOBlock?
    var inputQueue: DispatchQueue?
    var entered = DispatchSemaphore(value: 0)
    var resume = DispatchSemaphore(value: 0)
    func hit(_ name: String) -> Int { lock.lock(); defer { lock.unlock() }; counts[name, default: 0] += 1; return counts[name]! }
    func count(_ name: String) -> Int { lock.lock(); defer { lock.unlock() }; return counts[name, default: 0] }
    func reset(_ mode: String) { lock.lock(); defer { lock.unlock() }; counts = [:]; listeners = []; input = nil; inputQueue = nil; self.mode = mode; entered = DispatchSemaphore(value: 0); resume = DispatchSemaphore(value: 0) }
    func add(_ value: Listener) { lock.lock(); defer { lock.unlock() }; listeners.append(value) }
    func listener(_ index: Int) -> Listener { lock.lock(); defer { lock.unlock() }; return listeners[index] }
}
func AudioObjectGetPropertyData(_ object: AudioObjectID, _ address: UnsafePointer<AudioObjectPropertyAddress>, _ size: UInt32, _ qualifier: UnsafeRawPointer?, _ outputSize: UnsafeMutablePointer<UInt32>, _ output: UnsafeMutableRawPointer) -> OSStatus {
    switch address.pointee.mSelector {
    case kAudioHardwarePropertyTranslatePIDToProcessObject: output.assumingMemoryBound(to: AudioObjectID.self).pointee = 90
    case kAudioProcessPropertyPID: output.assumingMemoryBound(to: pid_t.self).pointee = 77
    case kAudioProcessPropertyBundleID: output.assumingMemoryBound(to: CFString.self).pointee = neteaseBundle as CFString
    case kAudioTapPropertyFormat:
        _ = HAL.shared.hit("format")
        if object == 0 { return kAudioHardwareBadObjectError }
        output.assumingMemoryBound(to: AudioStreamBasicDescription.self).pointee = AudioStreamBasicDescription(mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM, mFormatFlags: kAudioFormatFlagIsFloat, mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8, mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
    default: return kAudioHardwareUnknownPropertyError
    }
    return noErr
}
func AudioHardwareCreateProcessTap(_ description: CATapDescription, _ output: UnsafeMutablePointer<AudioObjectID>) -> OSStatus {
    let n = HAL.shared.hit("tap")
    if HAL.shared.mode == "error" { return kAudioHardwareIllegalOperationError }
    if HAL.shared.mode == "route-glitch" && n == 2 { return kAudioHardwareNotRunningError }
    output.pointee = HAL.shared.mode == "zero-tap" ? 0 : UInt32(100+n)
    return noErr
}
func AudioHardwareCreateAggregateDevice(_ description: CFDictionary, _ output: UnsafeMutablePointer<AudioObjectID>) -> OSStatus {
    let n = HAL.shared.hit("aggregate")
    if HAL.shared.mode == "blocked" && n == 1 { HAL.shared.entered.signal(); _ = HAL.shared.resume.wait(timeout: .now()+3) }
    output.pointee = HAL.shared.mode == "zero-device" ? 0 : UInt32(200+n)
    return noErr
}
func AudioDeviceCreateIOProcIDWithBlock(_ output: UnsafeMutablePointer<AudioDeviceIOProcID?>, _ device: AudioObjectID, _ queue: DispatchQueue?, _ block: @escaping AudioDeviceIOBlock) -> OSStatus {
    _ = HAL.shared.hit("io")
    HAL.shared.input = block; HAL.shared.inputQueue = queue
    if device == 0 { return kAudioHardwareBadObjectError }
    if HAL.shared.mode != "nil-io" { output.pointee = { _,_,_,_,_,_,_ in noErr } }
    return noErr
}
func AudioDeviceStart(_ device: AudioObjectID, _ proc: AudioDeviceIOProcID?) -> OSStatus { _ = HAL.shared.hit("start"); return noErr }
@discardableResult func AudioDeviceStop(_ device: AudioObjectID, _ proc: AudioDeviceIOProcID?) -> OSStatus { _ = HAL.shared.hit("stop"); return noErr }
@discardableResult func AudioDeviceDestroyIOProcID(_ device: AudioObjectID, _ proc: AudioDeviceIOProcID) -> OSStatus { _ = HAL.shared.hit("destroy-io"); return noErr }
@discardableResult func AudioHardwareDestroyAggregateDevice(_ device: AudioObjectID) -> OSStatus { _ = HAL.shared.hit("destroy-device"); return noErr }
@discardableResult func AudioHardwareDestroyProcessTap(_ tap: AudioObjectID) -> OSStatus { _ = HAL.shared.hit("destroy-tap"); return noErr }
func AudioObjectAddPropertyListenerBlock(_ object: AudioObjectID, _ address: UnsafePointer<AudioObjectPropertyAddress>, _ queue: DispatchQueue?, _ block: @escaping AudioObjectPropertyListenerBlock) -> OSStatus {
    HAL.shared.add(Listener(queue: queue, block: block, address: address.pointee)); _ = HAL.shared.hit("listener"); return noErr
}
@discardableResult func AudioObjectRemovePropertyListenerBlock(_ object: AudioObjectID, _ address: UnsafePointer<AudioObjectPropertyAddress>, _ queue: DispatchQueue?, _ block: @escaping AudioObjectPropertyListenerBlock) -> OSStatus { noErr }


@main struct InterruptionProbe {
    static func spin(_ seconds: Double) { let end = Date().addingTimeInterval(seconds); while Date() < end { RunLoop.current.run(until: min(end, Date().addingTimeInterval(0.01))) } }
    static func waitFor(_ condition: () -> Bool) -> Bool { let end = Date().addingTimeInterval(2); while !condition() && Date() < end { spin(0.01) }; return condition() }
    static func stop(_ audio: DesktopAudio) -> Bool { var done = false; audio.stop { done = true }; return waitFor { done } }
    static func emit() {
        guard let block = HAL.shared.input, let queue = HAL.shared.inputQueue else { return }
        queue.sync {
            var samples = (0..<4096).map { Float(sin(Double($0) * 0.05) * 0.5) }
            samples.withUnsafeMutableBytes { bytes in
                var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 2, mDataByteSize: UInt32(bytes.count), mData: bytes.baseAddress))
                var output = AudioBufferList(); var time = AudioTimeStamp()
                withUnsafePointer(to: &list) { data in
                    withUnsafePointer(to: &time) { stamp in
                        withUnsafeMutablePointer(to: &output) { block(stamp, data, stamp, $0, stamp) }
                    }
                }
            }
        }
    }
    static func main() {
        var results: [[String: Any]] = []
        func record(_ name: String, _ ok: Bool) { results.append(["case": name, "passed": ok]) }
        HAL.shared.reset("normal")
        var audio = DesktopAudio()
        var message = ""; var responsive = false; var lastRMS = 0.0
        audio.output = { features, text in message = text; lastRMS = features.rms; if features.rms > 0 { responsive = true } }
        audio.update(pid: 77, reason: "play")
        record("initial capture starts", waitFor { HAL.shared.count("listener") == 5 })
        emit(); spin(0.1)
        record("initial PCM drives rhythm", responsive)
        spin(2.3)
        record("PCM gap is static without guessing permission denial", lastRMS == 0 && !message.contains("权限") && !message.contains("未授权"))
        responsive = false
        for _ in 0..<5 { emit(); audio.update(pid: 77, reason: "play"); spin(0.08) }
        record("PCM resumes after gap without reopening or replacing tap", responsive && HAL.shared.count("tap") == 1 && HAL.shared.count("destroy-tap") == 0)
        audio.retry(); spin(0.15)
        record("retry on healthy capture does not recreate capture", HAL.shared.count("tap") == 1)
        record("gap capture exits", stop(audio))

        for mode in ["zero-tap", "error", "route-glitch"] {
            HAL.shared.reset(mode)
            audio = DesktopAudio(); message = ""; responsive = false
            audio.output = { features, text in message = text; if features.rms > 0 { responsive = true } }
            audio.update(pid: 77, reason: "play")
            _ = waitFor { HAL.shared.count("tap") == 1 }; spin(0.1)
            if mode == "route-glitch" {
                let listener = HAL.shared.listener(0)
                listener.queue?.async { var address = listener.address; listener.block(1, &address) }
                _ = waitFor { HAL.shared.count("tap") == 2 }; spin(0.1)
            }
            let attempts = HAL.shared.count("tap")
            for _ in 0..<10 { audio.update(pid: 77, reason: "play") }; spin(0.2)
            record(mode + " does not retry on status refresh or blame permission", HAL.shared.count("tap") == attempts && !message.contains("权限") && !message.contains("未授权"))
            HAL.shared.mode = "normal"
            audio.retry()
            record(mode + " explicit retry starts one new capture", waitFor { HAL.shared.count("start") == (mode == "route-glitch" ? 2 : 1) } && HAL.shared.count("tap") == attempts + 1)
            emit(); spin(0.1)
            record(mode + " retry restores real features", responsive)
            record(mode + " exits", stop(audio))
        }
        HAL.shared.reset("error")
        audio = DesktopAudio()
        audio.update(pid: 77, reason: "play"); _ = waitFor { HAL.shared.count("tap") == 1 }; spin(0.1)
        audio.update(pid: nil, reason: "hidden"); spin(0.1)
        HAL.shared.mode = "normal"; audio.retry(); spin(0.2)
        record("retry while hidden never captures", HAL.shared.count("tap") == 1)
        record("hidden capture exits", stop(audio))
        audio.retry(); audio.update(pid: 77, reason: "late"); spin(0.2)
        record("retry cannot undo exit", HAL.shared.count("tap") == 1)
        let data = try! JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
        exit(results.allSatisfy { $0["passed"] as? Bool == true } ? 0 : 1)
    }
}
