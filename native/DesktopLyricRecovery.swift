import Foundation

struct DesktopLyricRecoveryResult: Codable {
    let lines: [LyricLine]
    let community: CommunityLyricDocument?
    let message: String

    var readableText: String? {
        if let community {
            if community.instrumental { return "纯音乐" }
            if let plain = community.plainText { return plain }
            return community.lines.map { [$0.text, $0.translation].compactMap { $0 }.joined(separator: "\n") }.joined(separator: "\n")
        }
        return lines.isEmpty ? nil : lines.map(\.text).joined(separator: "\n")
    }
}

private let recoveryParsing = DispatchQueue(label: "com.likeit.desktop.lyric-recovery", qos: .userInitiated)

final class DesktopLyricRecovery {
    private enum Endpoint {
        case search, detail, lyrics, lrclib
        var host: String { self == .lrclib ? "lrclib.net" : "music.163.com" }
        var path: String {
            switch self {
            case .search: return "/api/search/get"
            case .detail: return "/api/song/detail"
            case .lyrics: return "/api/song/lyric"
            case .lrclib: return "/api/search"
            }
        }
    }
    private let lyrics: DesktopLyrics
    private let community: CommunityLyrics
    private let sessionConfiguration: URLSessionConfiguration
    private let configurationURL: URL
    private var official: OpenAPILyrics?
    private var configurationInvalid = false
    private var generation = UUID(), phase = UUID(), requestID = UUID()
    private var request: LyricRequest?
    private var requestTimeout: DispatchWorkItem?, phaseTimeout: DispatchWorkItem?, deadline: DispatchWorkItem?
    private var completion: ((DesktopLyricRecoveryResult) -> Void)?
    private var expires = 0.0
    private var verified: [SongCandidate] = []

    init(lyrics: DesktopLyrics, community: CommunityLyrics, sessionConfiguration: URLSessionConfiguration = .ephemeral,
         configurationURL: URL = OpenAPILyricConfiguration.defaultURL, cacheDirectory: URL? = nil, cacheNow: @escaping () -> Date = Date.init) {
        self.lyrics = lyrics; self.community = community
        self.sessionConfiguration = sessionConfiguration.copy() as! URLSessionConfiguration
        self.sessionConfiguration.httpAdditionalHeaders = nil
        self.configurationURL = configurationURL
    }

    func cancel() {
        generation = UUID()
        clearPhase()
        deadline?.cancel(); deadline = nil
        completion = nil
        verified = []
    }

    func stop() { cancel(); lyrics.stop(); community.stop() }

    private func clearPhase() {
        phase = UUID(); requestID = UUID()
        lyrics.cancel(); community.cancel(); official?.cancel()
        request?.cancel(); request = nil
        requestTimeout?.cancel(); requestTimeout = nil
        phaseTimeout?.cancel(); phaseTimeout = nil
    }

    func load(key: String, metadata: TrackMetadata, preferredSource: String, completion: @escaping (DesktopLyricRecoveryResult) -> Void) {
        cancel()
        self.completion = completion
        guard !normalized(metadata.title).isEmpty else { unavailable(); return }
        do {
            let configuration = try OpenAPILyricConfiguration.load(from: configurationURL)
            official = configuration.map { OpenAPILyrics(configuration: $0, sessionConfiguration: sessionConfiguration) }
            configurationInvalid = false
        } catch { official = nil; configurationInvalid = true }
        expires = ProcessInfo.processInfo.systemUptime + 20
        let token = generation
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.generation == token else { return }
            self.unavailable()
        }
        deadline = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: timeout)
        if matchedSongID(for: metadata, candidates: [SongCandidate(id: "1", metadata: metadata)]) == nil || LyricRequest.isCoolingDown("music.163.com") {
            search(metadata); return
        }
        beginPhase(seconds: 4) { [weak self] in self?.search(metadata) }
        let exactPhase = phase
        lyrics.load(key: key, metadata: metadata) { [weak self] lines, message in
            guard let self, self.generation == token, self.phase == exactPhase else { return }
            if DesktopLyrics.validCachedLines(lines) {
                self.finish(DesktopLyricRecoveryResult(lines: lines, community: nil, message: self.neteaseSource + " · 精确匹配 · " + message))
            } else { self.search(metadata) }
        }
    }

    private var neteaseSource: String { official == nil ? "网易公开" : "网易官方" }

    private func beginPhase(seconds: Double, onTimeout: @escaping () -> Void) {
        clearPhase()
        let token = generation, current = phase
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.generation == token, self.phase == current else { return }
            onTimeout()
        }
        phaseTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, min(seconds, expires - ProcessInfo.processInfo.systemUptime)), execute: timeout)
    }

    private func search(_ track: TrackMetadata) {
        // Reserve four seconds for each later source, even if Netease stalls.
        beginPhase(seconds: expires - ProcessInfo.processInfo.systemUptime - 8) { [weak self] in self?.loadAMLL(track) }
        fetch(.search, query: ["s": ([track.title] + track.artists).joined(separator: " "), "type": "1", "limit": "100", "offset": "0"], decode: { value -> [SongCandidate]? in
            guard let json = value as? [String: Any], jsonNumber(json["code"]) == 200,
                  let rows = (json["result"] as? [String: Any])?["songs"] as? [Any] else { return nil }
            return Self.ranked(rows.prefix(100).compactMap { ($0 as? [String: Any]).flatMap(Self.neteaseCandidate) }, for: track)
        }) { [weak self] candidates in self?.tryNetease(Array((candidates ?? []).prefix(3)), at: 0, track: track) }
    }

    private func tryNetease(_ candidates: [SongCandidate], at index: Int, track: TrackMetadata) {
        guard index < candidates.count else { loadAMLL(track); return }
        let candidate = candidates[index]
        fetch(.detail, query: ["ids": "[\(candidate.id)]"], decode: { value -> SongCandidate? in
            guard let json = value as? [String: Any], jsonNumber(json["code"]) == 200,
                  let rows = json["songs"] as? [[String: Any]], rows.count == 1,
                  let detail = Self.neteaseCandidate(rows[0]), detail.id == candidate.id, Self.matches(detail.metadata, track) else { return nil }
            return detail
        }) { [weak self] detail in
            guard let self else { return }
            let next = { [weak self] in self?.tryNetease(candidates, at: index + 1, track: track) }
            guard let detail else { next(); return }
            self.verified.append(detail)
            if self.configurationInvalid { next(); return }
            if let official = self.official {
                if LyricRequest.isCoolingDown("openapi.music.163.com") { next(); return }
                let token = self.generation, phase = self.phase
                official.load(originalID: detail.id, keyword: ([track.title] + track.artists).joined(separator: " ")) { [weak self] result in
                    guard let self, self.generation == token, self.phase == phase else { return }
                    if case .lines(let lines) = result, DesktopLyrics.validCachedLines(lines) { self.accept(lines: lines, candidate: detail) }
                    else { next() }
                }
            } else {
                self.fetch(.lyrics, query: ["id": detail.id, "lv": "-1", "kv": "-1", "tv": "-1"], decode: { value -> [LyricLine]? in
                    guard let json = value as? [String: Any], jsonNumber(json["code"]) == 200,
                          let text = (json["lrc"] as? [String: Any])?["lyric"] as? String else { return nil }
                    let lines = parseLRC(text)
                    return DesktopLyrics.validCachedLines(lines) ? lines : nil
                }) { [weak self] lines in
                    if let lines { self?.accept(lines: lines, candidate: detail) } else { next() }
                }
            }
        }
    }

    private func accept(lines: [LyricLine], candidate: SongCandidate) {
        finish(DesktopLyricRecoveryResult(lines: lines, community: nil, message: label(neteaseSource, candidate.metadata)))
    }

    private func loadAMLL(_ track: TrackMetadata) {
        beginPhase(seconds: 4) { [weak self] in self?.loadLRCLIB(track) }
        tryAMLL(at: 0, track: track)
    }

    private func tryAMLL(at index: Int, track: TrackMetadata) {
        guard index < verified.count else { loadLRCLIB(track); return }
        let candidate = verified[index]
        if LyricRequest.isCoolingDown("api.amll.dev") { loadLRCLIB(track); return }
        let token = generation, currentPhase = phase
        community.loadVerifiedAMLL(id: candidate.id) { [weak self] outcome in
            guard let self, self.generation == token, self.phase == currentPhase else { return }
            if let document = outcome.document { self.finish(DesktopLyricRecoveryResult(lines: [], community: document, message: self.label("AMLL", candidate.metadata))) }
            else { self.tryAMLL(at: index + 1, track: track) }
        }
    }

    private func loadLRCLIB(_ track: TrackMetadata) {
        beginPhase(seconds: 4) { [weak self] in self?.unavailable() }
        var query = ["track_name": track.title]
        if !track.artists.isEmpty { query["artist_name"] = track.artists.joined(separator: " / ") }
        fetch(.lrclib, query: query, decode: { value -> (SongCandidate, CommunityLyricDocument)? in
            guard let rows = value as? [Any] else { return nil }
            let records: [(SongCandidate, [String: Any])] = rows.prefix(20).compactMap { row in
                guard let row = row as? [String: Any], let id = Self.id(row["id"]), let title = row["trackName"] as? String else { return nil }
                let artist = row["artistName"] as? String ?? ""
                return (SongCandidate(id: id, metadata: TrackMetadata(title: title, artists: normalized(artist).isEmpty ? [] : [artist], album: row["albumName"] as? String ?? "", duration: jsonNumber(row["duration"]) ?? 0)), row)
            }
            let documents: [(SongCandidate, CommunityLyricDocument)] = Self.ranked(records.map(\.0), for: track).compactMap { candidate in
                guard let row = records.first(where: { $0.0.id == candidate.id })?.1,
                      let document = CommunityLyrics.lrclibDocument(row, duration: max(0, candidate.metadata.duration)) else { return nil }
                return (candidate, document)
            }
            for kind in 0...2 {
                if let match = documents.first(where: { (!$0.1.lines.isEmpty ? 0 : $0.1.plainText != nil ? 1 : 2) == kind }) { return match }
            }
            return nil
        }) { [weak self] result in
            guard let self else { return }
            if let (candidate, document) = result { self.finish(DesktopLyricRecoveryResult(lines: [], community: document, message: self.label("LRCLIB", candidate.metadata))) }
            else { self.unavailable() }
        }
    }

    private func label(_ source: String, _ metadata: TrackMetadata) -> String {
        source + " · 候选 · " + metadata.title + (metadata.artists.isEmpty ? "" : " / " + metadata.artists.joined(separator: " / "))
    }

    private func unavailable() { finish(DesktopLyricRecoveryResult(lines: [], community: nil, message: "暂时没有匹配的歌词")) }

    private func finish(_ result: DesktopLyricRecoveryResult) {
        let callback = completion
        cancel()
        callback?(result)
    }

    private func fetch<Value>(_ endpoint: Endpoint, query: [String: String], decode: @escaping (Any) -> Value?, completion: @escaping (Value?) -> Void) {
        if LyricRequest.isCoolingDown(endpoint.host) { completion(nil); return }
        let token = generation, currentPhase = phase, currentRequest = UUID()
        requestID = currentRequest
        var url = URLComponents()
        url.scheme = "https"; url.host = endpoint.host; url.path = endpoint.path
        url.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        url.percentEncodedQuery = url.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let address = url.url else { completion(nil); return }
        var payload = URLRequest(url: address, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 4)
        payload.setValue("Likeit/1.0", forHTTPHeaderField: "User-Agent")
        let done: (Value?) -> Void = { [weak self] value in
            guard let self, self.generation == token, self.phase == currentPhase, self.requestID == currentRequest else { return }
            self.requestID = UUID()
            self.requestTimeout?.cancel(); self.requestTimeout = nil
            self.request?.cancel(); self.request = nil
            completion(value)
        }
        let timeout = DispatchWorkItem { done(nil) }
        requestTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: timeout)
        let request = LyricRequest(sessionConfiguration: sessionConfiguration)
        self.request = request
        request.start(payload) { result in
            recoveryParsing.async {
                let value = (try? result.get()).flatMap { try? JSONSerialization.jsonObject(with: $0) }.flatMap(decode)
                DispatchQueue.main.async { done(value) }
            }
        }
    }

    private static func id(_ value: Any?) -> String? {
        guard let number = jsonNumber(value), number > 0, number.rounded() == number, number <= 9_007_199_254_740_991 else { return nil }
        return String(format: "%.0f", number)
    }

    private static func neteaseCandidate(_ row: [String: Any]) -> SongCandidate? {
        guard let id = id(row["id"]), let title = row["name"] as? String, !normalized(title).isEmpty else { return nil }
        let artists = (row["artists"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }.filter { !normalized($0).isEmpty }
        return SongCandidate(id: id, metadata: TrackMetadata(title: title, artists: artists, album: (row["album"] as? [String: Any])?["name"] as? String ?? "", duration: jsonNumber(row["duration"]).map { $0 / 1000 } ?? 0))
    }

    private static func matches(_ candidate: TrackMetadata, _ current: TrackMetadata) -> Bool {
        guard normalized(candidate.title) == normalized(current.title) else { return false }
        let known = current.artists.map(normalized).filter { !$0.isEmpty }, found = candidate.artists.map(normalized)
        return known.isEmpty || Set(known) == Set(found) || (known.count == 1 && known[0] == found.joined(separator: " / ")) || (found.count == 1 && found[0] == known.joined(separator: " / "))
    }

    private static func ranked(_ candidates: [SongCandidate], for track: TrackMetadata) -> [SongCandidate] {
        func album(_ item: SongCandidate) -> Bool { !normalized(track.album).isEmpty && normalized(item.metadata.album) == normalized(track.album) }
        func distance(_ item: SongCandidate) -> Double { track.duration > 0 && item.metadata.duration > 0 ? abs(item.metadata.duration - track.duration) : .infinity }
        var seen = Set<String>()
        return candidates.filter { matches($0.metadata, track) }.sorted {
            if album($0) != album($1) { return album($0) }
            if distance($0) != distance($1) { return distance($0) < distance($1) }
            return (UInt64($0.id) ?? 0) < (UInt64($1.id) ?? 0)
        }.filter { seen.insert($0.id).inserted }
    }
}
