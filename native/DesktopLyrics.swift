import Foundation

private enum LyricError: Error { case unavailable }

// One bounded request, with no credentials, cookies, cache, or cross-host redirects.
private final class LyricRequest: NSObject, URLSessionDataDelegate {
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var data = Data()
    private var completion: ((Result<Data, Error>) -> Void)?

    func start(_ url: URL, completion: @escaping (Result<Data, Error>) -> Void) {
        self.completion = completion
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        task = session!.dataTask(with: url)
        task!.resume()
    }
    func cancel() { task?.cancel() }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let valid = (response as? HTTPURLResponse)?.statusCode == 200 && response.expectedContentLength <= 1_048_576
        completionHandler(valid ? .allow : .cancel)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        if data.count + chunk.count > 1_048_576 { dataTask.cancel() } else { data.append(chunk) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let callback = completion
        completion = nil
        callback?(error.map { .failure($0) } ?? .success(data))
        data.removeAll()
        session.invalidateAndCancel()
        self.session = nil
        self.task = nil
    }
}

final class DesktopLyrics {
    private var request: LyricRequest?
    private var deadline: DispatchWorkItem?
    private var generation = UUID()
    private var cache: [(String, [LyricLine])] = []

    func cancel() {
        generation = UUID()
        request?.cancel(); request = nil
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
            self.cache.append((key, lines))
            if self.cache.count > 20 { self.cache.removeFirst() }
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
                self.fetch("/api/song/lyric", ["id": id, "lv": "-1", "kv": "-1", "tv": "-1"], token: token) { json in
                    guard let lrc = json?["lrc"] as? [String: Any], let text = lrc["lyric"] as? String else { finish([], "暂无可用歌词 · 空歌词或网络不可用"); return }
                    let lines = parseLRC(text)
                    finish(lines, lines.contains(where: { !$0.text.isEmpty }) ? "歌词按歌曲信息匹配" : "暂无可用歌词 · 无同步歌词")
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
        let request = LyricRequest()
        self.request = request
        request.start(address) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                guard let data = try? result.get(), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], jsonNumber(json["code"]) == 200 else { completion(nil); return }
                completion(json)
            }
        }
    }

    private static func candidate(_ data: [String: Any]) -> SongCandidate? {
        guard let id = jsonNumber(data["id"]), id > 0, id.rounded() == id, id <= 9_007_199_254_740_991,
              let title = data["name"] as? String, let artists = data["artists"] as? [[String: Any]], !artists.isEmpty,
              let album = (data["album"] as? [String: Any])?["name"] as? String,
              let duration = jsonNumber(data["duration"]), duration > 0 else { return nil }
        let names = artists.compactMap { $0["name"] as? String }
        guard names.count == artists.count, ([title, album] + names).allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return nil }
        return SongCandidate(id: String(format: "%.0f", id), metadata: TrackMetadata(title: title, artists: names, album: album, duration: duration / 1000))
    }
}
