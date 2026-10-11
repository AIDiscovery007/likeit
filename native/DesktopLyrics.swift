import Foundation
import CryptoKit
import Darwin

private let lyricParsing = DispatchQueue(label: "com.likeit.desktop.lyric-parsing", qos: .userInitiated)

final class DesktopLyrics {
    private var request: LyricRequest?
    private var deadline: DispatchWorkItem?
    private var generation = UUID()
    private var cache: [(String, [LyricLine])] = []
    private let sessionConfiguration: URLSessionConfiguration
    private var official: OpenAPILyrics?
    private var configurationInvalid = false
    private var cacheNamespace: String?
    private let configurationURL: URL
    private let diskCache: LyricDiskCache?
    private struct CachedLyrics: Codable { let lines: [LyricLine]; let message: String }

    init(sessionConfiguration: URLSessionConfiguration = .ephemeral, configurationURL: URL = OpenAPILyricConfiguration.defaultURL,
         cacheDirectory: URL? = nil, cacheNow: @escaping () -> Date = Date.init) {
        self.sessionConfiguration = sessionConfiguration.copy() as! URLSessionConfiguration
        self.configurationURL = configurationURL
        diskCache = cacheDirectory.map { LyricDiskCache(directory: $0, now: cacheNow) }
        configure()
    }

    private func configure() {
        do {
            let configuration = try OpenAPILyricConfiguration.load(from: configurationURL)
            official = configuration.map { OpenAPILyrics(configuration: $0, sessionConfiguration: sessionConfiguration) }
            cacheNamespace = try Self.namespace(for: configuration)
            configurationInvalid = false
        } catch {
            official = nil
            configurationInvalid = true
            cacheNamespace = nil
        }
    }

    static func namespace(for configuration: OpenAPILyricConfiguration?) throws -> String {
        guard let configuration else { return "netease-public" }
        let fields: [String: Any] = ["appID": configuration.appID, "token": configuration.accessToken,
                                     "device": configuration.device, "privateKey": configuration.privateKeyPEM,
                                     "lyricSource": configuration.lyricSource.rawValue]
        return "netease-official:" + LyricDiskCache.digest(try JSONSerialization.data(withJSONObject: fields, options: .sortedKeys))
    }

    func cancel() {
        generation = UUID()
        request?.cancel(); request = nil
        official?.cancel()
        deadline?.cancel(); deadline = nil
    }
    func stop() { cancel(); cache.removeAll() }

    func load(key: String, metadata: TrackMetadata, completion: @escaping ([LyricLine], String) -> Void) {
        cancel()
        if diskCache != nil { configure() }
        let diskKey = cacheNamespace.flatMap { LyricDiskCache.key(metadata: metadata, namespace: $0) }
        if let diskCache, let diskKey, let cached = diskCache.load(CachedLyrics.self, key: diskKey),
           Self.validCachedLines(cached.lines) {
            completion(cached.lines, cached.message + " · 本地缓存"); return
        }
        if diskCache == nil, let cached = cache.first(where: { $0.0 == key }) { completion(cached.1, cached.1.isEmpty ? "暂无可用歌词" : "歌词按歌曲信息匹配"); return }
        let token = generation
        let finish: ([LyricLine], String) -> Void = { [weak self] lines, message in
            guard let self, self.generation == token else { return }
            self.cancel()
            if let diskCache = self.diskCache, let diskKey, Self.validCachedLines(lines) {
                diskCache.store(CachedLyrics(lines: lines, message: message), key: diskKey)
            } else if self.diskCache == nil && self.official == nil && !self.configurationInvalid {
                self.cache.append((key, lines))
                if self.cache.count > 20 { self.cache.removeFirst() }
            }
            completion(lines, message)
        }
        let timeout = DispatchWorkItem { finish([], "暂无可用歌词 · 请求超时") }
        deadline = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeout)
        fetch("/api/search/get", ["s": metadata.title + " " + metadata.artists.joined(separator: " / "), "type": "1", "limit": "100", "offset": "0"], token: token) { [weak self] json in
            guard let self, let result = json?["result"] as? [String: Any], let total = jsonNumber(result["songCount"]), total >= 0, total.rounded() == total,
                  let songs = result["songs"] as? [[String: Any]], songs.count <= 100, total <= Double(songs.count) else { finish([], "暂无可用歌词 · 搜索结果不完整"); return }
            let candidates = songs.compactMap(Self.candidate)
            guard candidates.count == songs.count, let id = matchedSongID(for: metadata, candidates: candidates) else { finish([], "暂无可用歌词 · 无唯一完整匹配"); return }
            self.fetch("/api/song/detail", ["ids": "[\(id)]"], token: token) { [weak self] json in
                guard let self, let songs = json?["songs"] as? [[String: Any]], songs.count == 1, let candidate = Self.candidate(songs[0]), candidate.id == id, matchedSongID(for: metadata, candidates: [candidate]) == id else { finish([], "暂无可用歌词 · 详情未匹配"); return }
                if self.configurationInvalid { finish([], "官方歌词配置不可用 · 请检查配置、私钥及文件权限"); return }
                if let official = self.official {
                    official.load(originalID: id, keyword: metadata.title + " " + metadata.artists.joined(separator: " / ")) { outcome in
                        switch outcome {
                        case .lines(let lines): finish(lines, "歌词按歌曲信息匹配")
                        case .noSynchronizedLyrics: finish([], "暂无可用歌词 · 无同步歌词")
                        case .unavailable(let message): finish([], message)
                        }
                    }
                    return
                }
                self.fetch("/api/song/lyric", ["id": id, "lv": "-1", "kv": "-1", "tv": "-1"], token: token) { json in
                    guard let lrc = json?["lrc"] as? [String: Any], let text = lrc["lyric"] as? String else { finish([], "暂无可用歌词 · 空歌词或网络不可用"); return }
                    lyricParsing.async {
                        let lines = parseLRC(text)
                        DispatchQueue.main.async {
                            finish(lines, lines.contains(where: { !$0.text.isEmpty }) ? "歌词按歌曲信息匹配" : "暂无可用歌词 · 无同步歌词")
                        }
                    }
                }
            }
        }
    }

    private func fetch(_ path: String, _ query: [String: String], token: UUID, completion: @escaping ([String: Any]?) -> Void) {
        guard generation == token else { return }
        var url = URLComponents()
        url.scheme = "https"; url.host = "music.163.com"; url.path = path
        url.queryItems = query.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let address = url.url else { completion(nil); return }
        let request = LyricRequest(sessionConfiguration: sessionConfiguration)
        self.request = request
        request.start(URLRequest(url: address)) { [weak self] result in
            guard let self, self.generation == token else { return }
            lyricParsing.async {
                let json = (try? result.get()).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.generation == token else { return }
                    completion(jsonNumber(json?["code"]) == 200 ? json : nil)
                }
            }
        }
    }

    static func validCachedLines(_ lines: [LyricLine]) -> Bool {
        !lines.isEmpty && lines.count <= 20_000 && lines.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            && lines.allSatisfy { $0.time.isFinite && $0.time >= 0 }
            && zip(lines, lines.dropFirst()).allSatisfy { $0.time <= $1.time }
    }

    static func candidate(_ data: [String: Any]) -> SongCandidate? {
        guard let id = jsonNumber(data["id"]), id > 0, id.rounded() == id, id <= 9_007_199_254_740_991,
              let title = data["name"] as? String, let artists = data["artists"] as? [[String: Any]], !artists.isEmpty,
              let album = (data["album"] as? [String: Any])?["name"] as? String,
              let duration = jsonNumber(data["duration"]), duration > 0 else { return nil }
        let names = artists.compactMap { $0["name"] as? String }
        guard names.count == artists.count, ([title, album] + names).allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return nil }
        return SongCandidate(id: String(format: "%.0f", id), metadata: TrackMetadata(title: title, artists: names, album: album, duration: duration / 1000))
    }
}

// Shared storage is independent of provider models and never receives account credentials.
final class LyricDiskCache {
    static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/Likeit/Lyrics", isDirectory: true)
    }
    private struct Record<Value: Codable>: Codable {
        let schema: Int
        let key: String
        let createdAt: Double
        let value: Value
    }
    private static let lock = NSLock()
    private static let itemLimit = 1_048_576
    private let directory: URL
    private let now: () -> Date

    init(directory: URL, now: @escaping () -> Date) { self.directory = directory; self.now = now }

    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    static func key(metadata: TrackMetadata, namespace: String, neteaseID: String? = nil, allowsIncomplete: Bool = false) -> String? {
        guard !metadata.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, metadata.duration.isFinite,
              allowsIncomplete || (!metadata.artists.isEmpty && ([metadata.album] + metadata.artists).allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) && metadata.duration > 0) else { return nil }
        let fields: [String: Any] = ["title": metadata.title, "artists": metadata.artists, "album": metadata.album,
                                     "duration": metadata.duration, "namespace": namespace, "neteaseID": neteaseID as Any? ?? NSNull()]
        return (try? JSONSerialization.data(withJSONObject: fields, options: .sortedKeys)).map(digest)
    }

    func load<Value: Codable>(_ type: Value.Type, key: String) -> Value? {
        Self.lock.lock(); defer { Self.lock.unlock() }
        let directory = openDirectory()
        guard directory >= 0 else { return nil }
        defer { Darwin.close(directory) }
        let name = key + ".json"
        let file = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard file >= 0 else { return nil }
        defer { Darwin.close(file) }
        var info = stat()
        guard fstat(file, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(),
              info.st_size > 0, info.st_size <= Self.itemLimit, fchmod(file, 0o600) == 0 else { return nil }
        var bytes = Data(), buffer = [UInt8](repeating: 0, count: 8192)
        while bytes.count <= Self.itemLimit {
            let count = Darwin.read(file, &buffer, min(buffer.count, Self.itemLimit + 1 - bytes.count))
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { return nil }
            if count == 0 { break }
            bytes.append(contentsOf: buffer.prefix(count))
        }
        let time = now().timeIntervalSince1970
        guard bytes.count <= Self.itemLimit, let record = try? JSONDecoder().decode(Record<Value>.self, from: bytes),
              record.schema == 1, record.key == key, time.isFinite, record.createdAt.isFinite,
              time >= record.createdAt, time - record.createdAt < 30 * 86400 else {
            unlinkat(directory, name, 0); return nil
        }
        touch(file, at: time)
        return record.value
    }

    func store<Value: Codable>(_ value: Value, key: String) {
        let time = now().timeIntervalSince1970
        guard time.isFinite, let bytes = try? JSONEncoder().encode(Record(schema: 1, key: key, createdAt: time, value: value)),
              bytes.count <= Self.itemLimit else { return }
        Self.lock.lock(); defer { Self.lock.unlock() }
        let directory = openDirectory()
        guard directory >= 0 else { return }
        defer { Darwin.close(directory) }
        let temporary = "." + UUID().uuidString + ".tmp"
        // Acquire the writer lock during open, without an unlocked create-to-flock gap.
        let file = openat(directory, temporary, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_CLOEXEC | O_EXLOCK | O_NONBLOCK, 0o600)
        guard file >= 0 else { return }
        defer { unlinkat(directory, temporary, 0); Darwin.close(file) }
        let written = bytes.withUnsafeBytes { buffer -> Bool in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(file, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { return false }
                offset += count
            }
            return true
        }
        guard written, fsync(file) == 0 else { return }
        touch(file, at: time)
        guard renameat(directory, temporary, directory, key + ".json") == 0 else { return }
        prune(directory)
    }

    private func openDirectory() -> Int32 {
        guard directory.isFileURL, !directory.path.utf8.contains(0) else { return -1 }
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
        catch { return -1 }
        let file = Darwin.open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard file >= 0 else { return -1 }
        var info = stat()
        guard fstat(file, &info) == 0, info.st_uid == getuid(), fchmod(file, 0o700) == 0 else { Darwin.close(file); return -1 }
        return file
    }

    private func touch(_ file: Int32, at time: Double) {
        guard time >= 0, time < Double(Int.max) else { return }
        let timestamp = timeval(tv_sec: Int(time), tv_usec: Int32((time - floor(time)) * 1_000_000))
        var times = [timestamp, timestamp]
        _ = futimes(file, &times)
    }

    private func removeAbandonedTemporary(_ name: String, in directory: Int32) {
        let file = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard file >= 0 else { return }
        defer { Darwin.close(file) }
        var opened = stat(), current = stat()
        guard fstat(file, &opened) == 0, opened.st_mode & S_IFMT == S_IFREG, opened.st_uid == getuid(),
              flock(file, LOCK_EX | LOCK_NB) == 0,
              fstatat(directory, name, &current, AT_SYMLINK_NOFOLLOW) == 0,
              current.st_dev == opened.st_dev, current.st_ino == opened.st_ino else { return }
        unlinkat(directory, name, 0)
    }

    private func prune(_ directory: Int32) {
        let copy = dup(directory)
        guard copy >= 0 else { return }
        guard let stream = fdopendir(copy) else { Darwin.close(copy); return }
        defer { closedir(stream) }
        var entries: [(name: String, size: Int64, accessed: Double)] = []
        while let entry = readdir(stream) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) { String(cString: $0) }
            }
            if name.count == 41, name.hasPrefix("."), name.hasSuffix(".tmp"),
               UUID(uuidString: String(name.dropFirst().dropLast(4))) != nil {
                removeAbandonedTemporary(name, in: directory)
                continue
            }
            guard name.count == 69, name.hasSuffix(".json"), name.prefix(64).utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { continue }
            var info = stat()
            guard fstatat(directory, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { continue }
            guard info.st_mode & S_IFMT == S_IFREG, info.st_size > 0, info.st_size <= Self.itemLimit else { unlinkat(directory, name, 0); continue }
            entries.append((name, info.st_size, Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1_000_000_000))
        }
        var size = entries.reduce(Int64(0)) { $0 + $1.size }, count = entries.count
        for entry in entries.sorted(by: { $0.accessed == $1.accessed ? $0.name < $1.name : $0.accessed < $1.accessed }) {
            guard count > 200 || size > 20 * 1_048_576 else { break }
            if unlinkat(directory, entry.name, 0) == 0 { size -= entry.size; count -= 1 }
        }
    }
}
