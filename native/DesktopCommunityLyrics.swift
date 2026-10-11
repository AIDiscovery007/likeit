import Foundation

private let communityParsing = DispatchQueue(label: "com.likeit.desktop.community-lyrics", qos: .userInitiated)

// All mutable lifecycle state, including process-wide source cooldowns, lives on main.
final class CommunityLyrics {
    private struct CacheKey: Equatable {
        let trackKey: String
        let title: String
        let artists: [String]
        let album: String
        let duration: Double
        let neteaseID: String?
    }
    // Source policy is fixed to AMLL -> LRCLIB within this provider.
    private var cache: [(CacheKey, CommunityLyricOutcome)] = []
    private var cacheKey: CacheKey?
    private let diskCache: LyricDiskCache?
    private var diskKey: String?
    private static var cooldowns: [String: Date] = [:]
    private let sessionConfiguration: URLSessionConfiguration
    private var request: LyricRequest?
    private var deadline: DispatchWorkItem?
    private var generation = UUID()
    private var completion: ((CommunityLyricOutcome) -> Void)?

    init(sessionConfiguration: URLSessionConfiguration = .ephemeral, cacheDirectory: URL? = nil, cacheNow: @escaping () -> Date = Date.init) {
        diskCache = cacheDirectory.map { LyricDiskCache(directory: $0, now: cacheNow) }
        self.sessionConfiguration = sessionConfiguration.copy() as! URLSessionConfiguration
        self.sessionConfiguration.httpAdditionalHeaders = nil
    }

    func cancel() {
        guard Thread.isMainThread else { DispatchQueue.main.async { self.cancel() }; return }
        generation = UUID()
        completion = nil
        cacheKey = nil
        diskKey = nil
        request?.cancel(); request = nil
        deadline?.cancel(); deadline = nil
    }

    func stop() {
        guard Thread.isMainThread else { DispatchQueue.main.async { self.stop() }; return }
        cancel()
        cache.removeAll()
    }

    func load(key: String, metadata: TrackMetadata, neteaseID: String? = nil, completion: @escaping (CommunityLyricOutcome) -> Void) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.load(key: key, metadata: metadata, neteaseID: neteaseID, completion: completion) }; return
        }
        cancel()
        self.completion = completion
        guard matchedSongID(for: metadata, candidates: [SongCandidate(id: "1", metadata: metadata)]) != nil else {
            finish(nil, message: "社区歌词暂不可用 · 歌曲信息不完整"); return
        }
        diskKey = LyricDiskCache.key(metadata: metadata, namespace: "community-amll-lrclib", neteaseID: neteaseID)
        if let diskCache, let diskKey, let cached = diskCache.load(CommunityLyricOutcome.self, key: diskKey),
           let document = cached.document, Self.validCachedDocument(document) {
            cancel()
            completion(CommunityLyricOutcome(document: document, message: cached.message + " · 本地缓存")); return
        }
        let identity = CacheKey(trackKey: key, title: metadata.title, artists: metadata.artists, album: metadata.album, duration: metadata.duration, neteaseID: neteaseID)
        cacheKey = identity
        if diskCache == nil, let cached = cache.first(where: { $0.0 == identity }) {
            finish(cached.1.document, message: cached.1.message); return
        }
        let token = generation
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.generation == token else { return }
            self.finish(nil, message: "社区歌词暂不可用 · 请求超时")
        }
        deadline = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeout)
        if let id = neteaseID {
            if Self.validID(id) { loadAMLL(id: id, metadata: metadata, token: token) }
            else { loadLRCLIB(metadata: metadata, token: token) }
        } else {
            resolveID(metadata: metadata, token: token) { [weak self] id in
                guard let self else { return }
                if let id { self.loadAMLL(id: id, metadata: metadata, token: token) }
                else { self.loadLRCLIB(metadata: metadata, token: token) }
            }
        }
    }

    private func finish(_ document: CommunityLyricDocument?, message: String) {
        let callback = completion
        let outcome = CommunityLyricOutcome(document: document, message: message)
        if let diskCache, let diskKey, let document, Self.validCachedDocument(document) {
            diskCache.store(outcome, key: diskKey)
        } else if diskCache == nil, document != nil, let key = cacheKey {
            cache.removeAll { $0.0 == key }
            cache.append((key, outcome))
            if cache.count > 20 { cache.removeFirst() }
        }
        cancel()
        callback?(outcome)
    }

    private func resolveID(metadata: TrackMetadata, token: UUID, completion: @escaping (String?) -> Void) {
        fetch(host: "music.163.com", path: "/api/search/get", query: ["s": metadata.title + " " + metadata.artists.joined(separator: " / "), "type": "1", "limit": "100", "offset": "0"], token: token, decode: { json -> String? in
            guard jsonNumber(json["code"]) == 200, let result = json["result"] as? [String: Any],
                  let count = jsonNumber(result["songCount"]), count >= 0, count.rounded() == count,
                  let songs = result["songs"] as? [[String: Any]], songs.count <= 100, count == Double(songs.count) else { return nil }
            let candidates = songs.compactMap(DesktopLyrics.candidate)
            return candidates.count == songs.count ? matchedSongID(for: metadata, candidates: candidates) : nil
        }) { [weak self] id in
            guard let self, let id else { completion(nil); return }
            self.fetch(host: "music.163.com", path: "/api/song/detail", query: ["ids": "[\(id)]"], token: token, decode: { json -> String? in
                guard jsonNumber(json["code"]) == 200, let songs = json["songs"] as? [[String: Any]], songs.count == 1,
                      let candidate = DesktopLyrics.candidate(songs[0]), candidate.id == id,
                      matchedSongID(for: metadata, candidates: [candidate]) == id else { return nil }
                return id
            }, completion: completion)
        }
    }

    private func loadAMLL(id: String, metadata: TrackMetadata, token: UUID) {
        fetch(host: "api.amll.dev", path: "/v1/lyrics/get", query: ["ncmMusicId": id], token: token, decode: { json -> CommunityLyricDocument? in
            guard jsonNumber(json["status"]) == 200, let data = json["data"] as? [String: Any], data["format"] as? String == "ttml",
                  let ids = data["ncmMusicIds"] as? [String], ids.contains(id), let text = data["lyrics"] as? String else { return nil }
            let lines = parseCommunityTTML(text)
            return lines.isEmpty ? nil : CommunityLyricDocument(source: .amll, lines: lines, plainText: nil, instrumental: false)
        }) { [weak self] document in
            guard let self else { return }
            if let document { self.finish(document, message: "AMLL · 社区网易 ID 关联 · " + (document.lines.contains { !$0.words.isEmpty } ? "逐词歌词" : "逐行歌词")) }
            else { self.loadLRCLIB(metadata: metadata, token: token) }
        }
    }

    private func loadLRCLIB(metadata: TrackMetadata, token: UUID) {
        let artists = metadata.artists.joined(separator: " / ")
        fetch(host: "lrclib.net", path: "/api/get", query: ["track_name": metadata.title, "artist_name": artists, "album_name": metadata.album, "duration": String(metadata.duration)], token: token, decode: { json -> CommunityLyricDocument? in
            guard let title = json["trackName"] as? String, let artist = json["artistName"] as? String, let album = json["albumName"] as? String,
                  let duration = jsonNumber(json["duration"]), let flag = json["instrumental"] as? NSNumber, CFGetTypeID(flag) == CFBooleanGetTypeID() else { return nil }
            let current = TrackMetadata(title: metadata.title, artists: [artists], album: metadata.album, duration: metadata.duration)
            let candidate = SongCandidate(id: "1", metadata: TrackMetadata(title: title, artists: [artist], album: album, duration: duration))
            guard matchedSongID(for: current, candidates: [candidate]) != nil else { return nil }
            for field in ["syncedLyrics", "plainLyrics"] {
                if let value = json[field], !(value is NSNull), !(value is String) { return nil }
            }
            let synced = json["syncedLyrics"] as? String ?? "", plain = json["plainLyrics"] as? String ?? ""
            let hasSynced = !synced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasPlain = !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if flag.boolValue {
                return hasSynced || hasPlain ? nil : CommunityLyricDocument(source: .lrclib, lines: [], plainText: nil, instrumental: true)
            }
            let lines = communityLRCLines(synced, duration: metadata.duration)
            if !lines.isEmpty { return CommunityLyricDocument(source: .lrclib, lines: lines, plainText: nil, instrumental: false) }
            return hasPlain ? CommunityLyricDocument(source: .lrclib, lines: [], plainText: plain, instrumental: false) : nil
        }) { [weak self] document in
            let kind = document.map { $0.instrumental ? "纯音乐" : $0.plainText != nil ? "未同步歌词" : "逐行歌词" }
            self?.finish(document, message: kind.map { "LRCLIB · 完整歌曲信息匹配 · " + $0 } ?? "社区歌词暂不可用 · 未找到匹配内容或服务不可用")
        }
    }

    private func fetch<T>(host: String, path: String, query: [String: String], token: UUID, decode: @escaping ([String: Any]) -> T?, completion: @escaping (T?) -> Void) {
        guard generation == token else { return }
        if let until = Self.cooldowns[host], until > Date() { completion(nil); return }
        var url = URLComponents()
        url.scheme = "https"; url.host = host; url.path = path
        url.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        url.percentEncodedQuery = url.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let address = url.url else { completion(nil); return }
        var payload = URLRequest(url: address, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        payload.httpMethod = "GET"
        payload.setValue("Likeit/1.0", forHTTPHeaderField: "User-Agent")
        let request = LyricRequest(sessionConfiguration: sessionConfiguration)
        self.request = request
        request.start(payload, responseReceived: { response in
            if response.statusCode == 429 { Self.cooldowns[host] = Self.retryDate(response.value(forHTTPHeaderField: "Retry-After")) }
        }) { [weak self] result in
            guard let self, self.generation == token else { return }
            communityParsing.async {
                let value = (try? result.get()).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }.flatMap(decode)
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.generation == token else { return }
                    completion(value)
                }
            }
        }
    }

    private static func validCachedDocument(_ document: CommunityLyricDocument) -> Bool {
        if document.instrumental { return document.source == .lrclib && document.lines.isEmpty && document.plainText == nil }
        if let plain = document.plainText {
            return document.source == .lrclib && document.lines.isEmpty && !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !document.lines.isEmpty, document.lines.count + document.lines.reduce(0, { $0 + $1.words.count }) <= 20_000,
              document.lines.contains(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              zip(document.lines, document.lines.dropFirst()).allSatisfy({ $0.start <= $1.start }) else { return false }
        return document.lines.allSatisfy { line in
            guard line.start.isFinite, line.end.isFinite, line.start >= 0, line.end >= line.start,
                  zip(line.words, line.words.dropFirst()).allSatisfy({ $0.start <= $1.start }) else { return false }
            var previousEnd = 0
            return line.words.allSatisfy { word in
                guard document.source == .amll, word.start.isFinite, word.end.isFinite, word.start >= line.start,
                      word.end > word.start, word.end <= line.end, let recorded = word.utf16Range,
                      recorded.location >= previousEnd, recorded.location <= line.text.utf16.count,
                      recorded.length > 0, recorded.length <= line.text.utf16.count - recorded.location,
                      let range = Range(recorded, in: line.text), line.text[range] == word.text else { return false }
                previousEnd = recorded.location + recorded.length
                return true
            }
        }
    }

    private static func validID(_ id: String) -> Bool {
        id.utf8.first.map { (49...57).contains($0) } == true && id.utf8.allSatisfy { (48...57).contains($0) }
    }

    private static func retryDate(_ value: String?) -> Date {
        if let value, let seconds = Double(value), seconds.isFinite, seconds >= 0 { return Date().addingTimeInterval(seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return value.flatMap(formatter.date(from:)).map { max(Date(), $0) } ?? Date().addingTimeInterval(60)
    }
}
