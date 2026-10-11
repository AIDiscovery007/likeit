import Foundation

private let lyricParsing = DispatchQueue(label: "com.likeit.desktop.lyric-parsing", qos: .userInitiated)

final class DesktopLyrics {
    private var request: LyricRequest?
    private var deadline: DispatchWorkItem?
    private var generation = UUID()
    private var cache: [(String, [LyricLine])] = []
    private let sessionConfiguration: URLSessionConfiguration
    private let official: OpenAPILyrics?
    private let configurationInvalid: Bool

    init(sessionConfiguration: URLSessionConfiguration = .ephemeral, configurationURL: URL = OpenAPILyricConfiguration.defaultURL) {
        self.sessionConfiguration = sessionConfiguration.copy() as! URLSessionConfiguration
        do {
            official = try OpenAPILyricConfiguration.load(from: configurationURL).map { OpenAPILyrics(configuration: $0, sessionConfiguration: sessionConfiguration) }
            configurationInvalid = false
        } catch {
            official = nil
            configurationInvalid = true
        }
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
        if let cached = cache.first(where: { $0.0 == key }) { completion(cached.1, cached.1.isEmpty ? "暂无可用歌词" : "歌词按歌曲信息匹配"); return }
        let token = generation
        let finish: ([LyricLine], String) -> Void = { [weak self] lines, message in
            guard let self, self.generation == token else { return }
            self.cancel()
            if self.official == nil && !self.configurationInvalid {
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
