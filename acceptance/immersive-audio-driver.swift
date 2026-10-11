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
    var entered = DispatchSemaphore(value: 0)
    var resume = DispatchSemaphore(value: 0)
    func hit(_ name: String) -> Int { lock.lock(); defer { lock.unlock() }; counts[name, default: 0] += 1; return counts[name]! }
    func count(_ name: String) -> Int { lock.lock(); defer { lock.unlock() }; return counts[name, default: 0] }
    func reset(_ mode: String) { lock.lock(); defer { lock.unlock() }; counts = [:]; listeners = []; self.mode = mode; entered = DispatchSemaphore(value: 0); resume = DispatchSemaphore(value: 0) }
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

@main struct AudioProbe {
    static func spin(_ seconds: Double) { let end = Date().addingTimeInterval(seconds); while Date() < end { RunLoop.current.run(until: min(end,Date().addingTimeInterval(0.01))) } }
    static func waitFor(_ condition: () -> Bool) -> Bool { let end = Date().addingTimeInterval(2); while !condition() && Date() < end { spin(0.01) }; return condition() }
    static func stop(_ audio: DesktopAudio) -> Bool { var done = false; audio.stop { done = true }; return waitFor { done } }
    static func fire(_ listener: Listener) { listener.queue?.async { var address = listener.address; listener.block(1, &address) } }
    static func main() {
        var results: [[String:Any]] = []
        func record(_ name: String, _ ok: Bool) { results.append(["case":name,"passed":ok]) }
        // Hold the actual production start() inside the HAL call observed in the real trace.
        for scenario in ["P-nil-P", "P-nil", "P-stop-P"] {
            HAL.shared.reset("blocked")
            let audio = DesktopAudio()
            audio.update(pid:77,reason:"play")
            let entered = HAL.shared.entered.wait(timeout:.now()+2) == .success
            var stopped = false
            if scenario == "P-stop-P" { audio.stop { stopped = true } }
            else { audio.update(pid:nil,reason:"hidden") }
            if scenario != "P-nil" { audio.update(pid:77,reason:"play") }
            HAL.shared.resume.signal()
            spin(0.25)
            if scenario == "P-nil-P" {
                record(scenario, entered && HAL.shared.count("tap") == 1 && HAL.shared.count("start") == 1 && HAL.shared.count("destroy-tap") == 0)
            } else {
                record(scenario, entered && HAL.shared.count("start") == 0 && HAL.shared.count("destroy-tap") == 1 && (scenario != "P-stop-P" || stopped))
            }
            record(scenario+" cleanup",stop(audio))
        }
        for mode in ["zero-tap","zero-device","nil-io","error"] {
            HAL.shared.reset(mode)
            let audio = DesktopAudio()
            audio.update(pid:77,reason:"play")
            _ = waitFor { HAL.shared.count("tap") > 0 }
            spin(0.08)
            for _ in 0..<4 { audio.update(pid:77,reason:"play") }
            spin(0.08)
            let next = mode == "zero-tap" ? "format" : mode == "zero-device" ? "io" : "start"
            record(mode,HAL.shared.count("tap") == 1 && HAL.shared.count(next) == 0)
            record(mode+" cleanup",stop(audio))
        }
        HAL.shared.reset("normal")
        let audio = DesktopAudio()
        audio.update(pid:77,reason:"play")
        let firstReady = waitFor { HAL.shared.count("listener") == 5 }
        if firstReady {
            let old = HAL.shared.listener(0)
            audio.update(pid:nil,reason:"hidden")
            _ = waitFor { HAL.shared.count("destroy-tap") == 1 }
            audio.update(pid:77,reason:"play")
            let newReady = waitFor { HAL.shared.count("listener") == 10 }
            fire(old)
            spin(0.1)
            record("stale listener cannot rebuild new capture",newReady && HAL.shared.count("tap") == 2 && HAL.shared.count("destroy-tap") == 1)
        } else { record("stale listener cannot rebuild new capture",false) }
        record("stale listener cleanup",stop(audio))
        let bytes = try! JSONSerialization.data(withJSONObject:results,options:[.prettyPrinted,.sortedKeys])
        print(String(decoding:bytes,as:UTF8.self))
        exit(results.allSatisfy { $0["passed"] as? Bool == true } ? 0 : 1)
    }
}
