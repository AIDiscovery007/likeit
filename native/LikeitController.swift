import AppKit
import ApplicationServices
import Darwin
import Foundation

let bundleID = "com.netease.163music"
let nativeDirectory = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let limit = 64 * 1024
let parentPID = getppid()
let childLock = NSLock()
var mediaPID: pid_t = 0

func terminateController(_ code: Int32) -> Never {
    childLock.lock()
    if mediaPID > 0 { kill(mediaPID, SIGKILL) }
    childLock.unlock()
    _exit(code)
}

enum ControllerError: Error { case unavailable, timeout, outputLimit, uncertain }

func reply(_ value: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else { exit(1) }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([10]))
}

func currentPID() -> pid_t? {
    let applications = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    return applications.count == 1 ? applications[0].processIdentifier : nil
}

func mediaData() throws -> [String: Any] {
    let task = Process()
    let output = Pipe(), errors = Pipe()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
    task.arguments = [nativeDirectory.appendingPathComponent("mediaremote-adapter.pl").path,
                      nativeDirectory.appendingPathComponent("MediaRemoteAdapter.framework").path,
                      "get", "--no-artwork"]
    task.environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("MEDIAREMOTEADAPTER_") }
    task.standardInput = FileHandle.nullDevice
    task.standardOutput = output
    task.standardError = errors
    try task.run()
    childLock.lock()
    mediaPID = task.processIdentifier
    childLock.unlock()
    defer {
        if task.isRunning { kill(task.processIdentifier, SIGKILL) }
        task.waitUntilExit()
        childLock.lock()
        mediaPID = 0
        childLock.unlock()
        try? output.fileHandleForReading.close()
        try? errors.fileHandleForReading.close()
    }
    let handles = [output.fileHandleForReading, errors.fileHandleForReading]
    var descriptors = handles.map { pollfd(fd: $0.fileDescriptor, events: Int16(POLLIN), revents: 0) }
    for handle in handles { _ = fcntl(handle.fileDescriptor, F_SETFL, O_NONBLOCK) }
    var buffers = [Data(), Data()]
    let deadline = ProcessInfo.processInfo.systemUptime + 4
    while descriptors.contains(where: { $0.fd >= 0 }) || task.isRunning {
        if ProcessInfo.processInfo.systemUptime >= deadline { throw ControllerError.timeout }
        let polled = poll(&descriptors, nfds_t(descriptors.count), 50)
        if polled < 0 && errno != EINTR { throw ControllerError.unavailable }
        for index in descriptors.indices where descriptors[index].fd >= 0 && descriptors[index].revents != 0 {
            var bytes = [UInt8](repeating: 0, count: 4096)
            let count = Darwin.read(descriptors[index].fd, &bytes, bytes.count)
            if count > 0 {
                buffers[index].append(contentsOf: bytes.prefix(count))
                if buffers[0].count + buffers[1].count > limit { throw ControllerError.outputLimit }
            } else if count == 0 {
                descriptors[index].fd = -1
            } else if errno != EAGAIN && errno != EINTR { throw ControllerError.unavailable }
        }
    }
    guard task.terminationStatus == 0 else { throw ControllerError.unavailable }
    let value = try JSONSerialization.jsonObject(with: buffers[0], options: [.fragmentsAllowed])
    if value is NSNull { return [:] }
    guard let dictionary = value as? [String: Any] else { throw ControllerError.unavailable }
    return dictionary
}

struct Media {
    let key: String
    let playing: Bool
    let title: String
}

func media(pid: pid_t) throws -> Media? {
    let data = try mediaData()
    guard data["bundleIdentifier"] as? String == bundleID,
          let process = data["processIdentifier"] as? NSNumber,
          CFGetTypeID(process) != CFBooleanGetTypeID(), process.doubleValue == Double(pid),
          let playing = data["playing"] as? NSNumber, CFGetTypeID(playing) == CFBooleanGetTypeID(),
          let duration = data["duration"] as? NSNumber, CFGetTypeID(duration) != CFBooleanGetTypeID(),
          duration.doubleValue.isFinite, duration.doubleValue > 0 else { return nil }
    let names = ["contentItemIdentifier", "title", "artist", "album"]
    var fields: [String] = []
    for name in names {
        guard let value = data[name] as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, value.utf8.count <= 4096 else { return nil }
        fields.append(value)
    }
    let parts: [Any] = [bundleID, Int(pid), fields[0], fields[1], fields[2], fields[3], duration]
    let keyData = try JSONSerialization.data(withJSONObject: parts)
    guard let key = String(data: keyData, encoding: .utf8) else { return nil }
    return Media(key: key, playing: playing.boolValue, title: fields[1])
}

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    AXUIElementSetMessagingTimeout(element, 0.2)
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

func children(_ element: AXUIElement) -> [AXUIElement] {
    (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
}

let likeTitles = ["Like", "喜欢歌曲"]
let dislikeTitles = ["Dislike", "取消喜欢"]
let playTitles = ["Play", "播放"]
let pauseTitles = ["Pause", "暂停"]

struct Menu {
    let playing: Bool
    let liked: Bool
    let likeItem: AXUIElement
}

func menu(pid: pid_t) -> Menu? {
    let application = AXUIElementCreateApplication(pid)
    guard let barValue = attribute(application, kAXMenuBarAttribute), CFGetTypeID(barValue) == AXUIElementGetTypeID() else { return nil }
    let bar = unsafeBitCast(barValue, to: AXUIElement.self)
    let tops = children(bar)
    guard tops.count <= 20 else { return nil }
    var likes: [(AXUIElement, String)] = [], playback: [String] = []
    for top in tops {
        for submenu in children(top) {
            guard attribute(submenu, kAXRoleAttribute) as? String == kAXMenuRole else { continue }
            let entries = children(submenu)
            guard entries.count <= 100 else { return nil }
            for item in entries {
                guard attribute(item, kAXRoleAttribute) as? String == kAXMenuItemRole,
                      attribute(item, kAXEnabledAttribute) as? Bool == true,
                      let title = attribute(item, kAXTitleAttribute) as? String else { continue }
                if (likeTitles + dislikeTitles).contains(title) { likes.append((item, title)) }
                if (playTitles + pauseTitles).contains(title) { playback.append(title) }
            }
        }
    }
    guard likes.count == 1, playback.count == 1 else { return nil }
    return Menu(playing: pauseTitles.contains(playback[0]), liked: dislikeTitles.contains(likes[0].1), likeItem: likes[0].0)
}

struct Snapshot {
    var state = "unknown"
    var media: Media?
    var menu: Menu?
    var json: [String: Any] {
        var result: [String: Any] = ["state": state, "trackKey": media?.key as Any? ?? NSNull(), "liked": menu?.liked as Any? ?? NSNull()]
        if let title = media?.title { result["title"] = title }
        return result
    }
}

func snapshot() throws -> Snapshot {
    let applications = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    if applications.isEmpty { return Snapshot(state: "not-running") }
    guard applications.count == 1 else { return Snapshot() }
    let pid = applications[0].processIdentifier
    guard AXIsProcessTrusted() else { return Snapshot(state: "permission-required") }
    guard let before = try media(pid: pid), let control = menu(pid: pid),
          let after = try media(pid: pid), currentPID() == pid,
          before.key == after.key, before.playing == after.playing,
          after.playing == control.playing else {
        return Snapshot(state: AXIsProcessTrusted() ? "unknown" : "permission-required")
    }
    return Snapshot(state: after.playing ? "playing" : "paused", media: after, menu: control)
}

// One controller owns the lock across the entire TypeScript flow, including confirmation.
// Never unlink this file: competing processes must lock the same inode.
guard parentPID > 1, CommandLine.arguments.count == 2, CommandLine.arguments[1].hasPrefix("/") else { exit(1) }
let lock = open(CommandLine.arguments[1], O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
guard lock >= 0 else { reply(["error": "lock-unavailable"]); exit(1) }
guard flock(lock, LOCK_EX | LOCK_NB) == 0 else {
    if errno == EWOULDBLOCK { reply(["busy": true]) } else { reply(["error": "lock-unavailable"]) }
    close(lock)
    exit(0)
}
defer { close(lock) }
signal(SIGPIPE, SIG_IGN)
DispatchQueue.global().asyncAfter(deadline: .now() + 30) { terminateController(124) }
let parentMonitor = DispatchSource.makeTimerSource(queue: .global())
parentMonitor.schedule(deadline: .now(), repeating: .milliseconds(100))
parentMonitor.setEventHandler { if getppid() != parentPID { terminateController(125) } }
parentMonitor.resume()
reply(["ready": true])
var pressed = false
while let line = readLine() {
    guard line.utf8.count <= limit,
          let bytes = line.data(using: .utf8),
          let request = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { exit(1) }
    do {
        switch request["command"] as? String {
        case "read":
            reply(["snapshot": try snapshot().json])
        case "press":
            guard !pressed, let expected = request["trackKey"] as? String, !expected.isEmpty else { throw ControllerError.unavailable }
            let current = try snapshot()
            guard let identity = current.media else { reply(["action": "unavailable"]); continue }
            guard identity.key == expected else { reply(["action": "changed"]); continue }
            guard current.state == "playing", let control = current.menu else { reply(["action": "unavailable"]); continue }
            if control.liked { reply(["action": "already-liked"]); continue }
            guard attribute(control.likeItem, kAXEnabledAttribute) as? Bool == true,
                  let title = attribute(control.likeItem, kAXTitleAttribute) as? String,
                  likeTitles.contains(title) else { reply(["action": "unavailable"]); continue }
            guard getppid() == parentPID else { terminateController(125) }
            pressed = true
            guard AXUIElementPerformAction(control.likeItem, kAXPressAction as CFString) == .success else { throw ControllerError.uncertain }
            reply(["action": "pressed"])
        default: throw ControllerError.unavailable
        }
    } catch {
        reply(["error": "native-operation-failed"])
    }
}
