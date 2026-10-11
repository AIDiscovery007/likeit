import AppKit
import Darwin

let neteaseBundle = "com.netease.163music"
func neteasePID() -> pid_t? {
    let apps = NSRunningApplication.runningApplications(withBundleIdentifier: neteaseBundle)
    return apps.count == 1 && !apps[0].isTerminated ? apps[0].processIdentifier : nil
}

func jsonNumber(_ value: Any?) -> Double? {
    guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else { return nil }
    return value.doubleValue
}

struct DesktopSnapshot {
    let key: String
    let pid: pid_t
    let metadata: TrackMetadata
    let playing: Bool
    let rate: Double?
    let elapsed: Double?
    let sampledAt: Double

    init?(_ data: [String: Any], expectedPID: pid_t? = neteasePID()) {
        guard let pid = expectedPID, data["bundleIdentifier"] as? String == neteaseBundle,
              jsonNumber(data["processIdentifier"]) == Double(pid),
              let playing = data["playing"] as? NSNumber, CFGetTypeID(playing) == CFBooleanGetTypeID() else { return nil }
        let duration = max(0, jsonNumber(data["durationMicros"]).map { $0 / 1_000_000 } ?? 0)
        var fields: [String] = []
        for name in ["contentItemIdentifier", "title", "artist", "album"] {
            let value = data[name] as? String ?? ""
            if name == "title", value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || value.utf8.count > 4096 { return nil }
            fields.append(value.utf8.count <= 4096 ? value : "")
        }
        guard let bytes = try? JSONSerialization.data(withJSONObject: [neteaseBundle, Int(pid), fields[0], fields[1], fields[2], fields[3], duration]), let key = String(data: bytes, encoding: .utf8) else { return nil }
        self.key = key
        self.pid = pid
        metadata = TrackMetadata(title: fields[1], artists: fields[2].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : [fields[2]], album: fields[3], duration: duration)
        self.playing = playing.boolValue
        sampledAt = ProcessInfo.processInfo.systemUptime
        let rawRate = jsonNumber(data["playbackRate"])
        let timestamp = jsonNumber(data["timestampEpochMicros"]).map { $0 / 1_000_000 }
        let rawElapsed = jsonNumber(data["elapsedTimeMicros"]).map { $0 / 1_000_000 }
        if duration > 0, let rawRate, (0...4).contains(rawRate), playing.boolValue == (rawRate > 0),
           let timestamp, timestamp > 0, timestamp <= Date().timeIntervalSince1970,
           let rawElapsed, rawElapsed >= 0 {
            let position = rawElapsed + (Date().timeIntervalSince1970 - timestamp) * rawRate
            elapsed = position.isFinite ? min(duration, position) : nil
            rate = rawRate
        } else { elapsed = nil; rate = nil }
    }
}

// Each reader owns and reaps its sole Perl child. No controller or collection lock is involved.
final class DesktopMediaProcess {
    private let lock = NSLock()
    private var pid: pid_t = 0
    private var stopped = false

    func stop() {
        lock.lock(); defer { lock.unlock() }
        stopped = true
        if pid > 0 { kill(pid, SIGKILL) }
    }

    func run(stream: Bool, receive: ([String: Any]?) -> Void) {
        guard let resources = Bundle.main.resourceURL else { receive(nil); return }
        var output: [Int32] = [-1, -1]
        guard pipe(&output) == 0 else { receive(nil); return }
        defer { for fd in output where fd >= 0 { Darwin.close(fd) } }
        for fd in output { _ = fcntl(fd, F_SETFD, FD_CLOEXEC) }
        var actions: posix_spawn_file_actions_t?
        guard posix_spawn_file_actions_init(&actions) == 0 else { receive(nil); return }
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, output[1], STDOUT_FILENO)
        let args = ["/usr/bin/perl", resources.appendingPathComponent("mediaremote-adapter.pl").path, resources.appendingPathComponent("MediaRemoteAdapter.framework").path, stream ? "stream" : "get", "--no-artwork", "--micros"] + (stream ? ["--no-diff"] : [])
        var argv = args.map { strdup($0) } + [nil]
        var envp = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("MEDIAREMOTEADAPTER_") }.map { strdup($0.key + "=" + $0.value) } + [nil]
        defer { for pointer in argv + envp { free(pointer) } }
        var child: pid_t = 0
        lock.lock()
        let result = stopped ? ECANCELED : posix_spawn(&child, "/usr/bin/perl", &actions, nil, &argv, &envp)
        if result == 0 { pid = child }
        lock.unlock()
        guard result == 0 else { receive(nil); return }
        defer {
            lock.lock()
            kill(child, SIGKILL)
            var status: Int32 = 0
            while waitpid(child, &status, 0) < 0 && errno == EINTR {}
            pid = 0
            lock.unlock()
        }
        Darwin.close(output[1]); output[1] = -1
        _ = fcntl(output[0], F_SETFL, O_NONBLOCK)
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        var buffer = Data()
        var bytes = [UInt8](repeating: 0, count: 4096)
        while stream || ProcessInfo.processInfo.systemUptime < deadline {
            lock.lock(); let cancelled = stopped; lock.unlock()
            if cancelled { return }
            var descriptor = pollfd(fd: output[0], events: Int16(POLLIN), revents: 0)
            let polled = poll(&descriptor, 1, 50)
            if polled < 0 && errno != EINTR { break }
            if polled <= 0 { continue }
            let count = Darwin.read(output[0], &bytes, bytes.count)
            if count < 0 && (errno == EAGAIN || errno == EINTR) { continue }
            if count <= 0 { break }
            buffer.append(contentsOf: bytes.prefix(count))
            if buffer.count > 65_536 { break }
            while let newline = buffer.firstIndex(of: 10) {
                let line = buffer.prefix(upTo: newline)
                guard let data = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { receive(nil); return }
                if stream {
                    if data["type"] as? String == "data", data["diff"] as? Bool == false { receive(data["payload"] as? [String: Any]) }
                } else { receive(data) }
                buffer.removeSubrange(...newline)
                if !stream { return }
            }
        }
        if !stream, !buffer.isEmpty, let data = try? JSONSerialization.jsonObject(with: buffer) as? [String: Any] { receive(data) }
        else { receive(nil) }
    }
}
