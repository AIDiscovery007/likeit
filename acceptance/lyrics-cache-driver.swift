import Foundation

private let fixtureTrack = TrackMetadata(title: "Cache Song", artists: ["Cache Artist"], album: "Cache Album", duration: 180)
private let fixtureTTML = """
<tt xmlns="http://www.w3.org/ns/ttml" xmlns:ttm="http://www.w3.org/ns/ttml#metadata"><body><div><p begin="1" end="5">go <span begin="3" end="4">go</span><span ttm:role="x-translation" xml:lang="zh-CN">向前</span></p></div></body></tt>
"""

private final class CacheHTTP: URLProtocol {
    static var requests: [URLRequest] = []
    static var handle: ((CacheHTTP) -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.requests.append(request); DispatchQueue.main.async { Self.handle?(self) } }
    override func stopLoading() {}
    func send(_ object: Any, status: Int = 200) {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: [:])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: object))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@main struct LyricsCacheAcceptance {
    static func main() throws {
        let fm = FileManager.default
        let stage = CommandLine.arguments[1], root = URL(fileURLWithPath: CommandLine.arguments[2])
        let directory = root.appendingPathComponent("cache")
        let keyURL = root.appendingPathComponent("fixture-private.pem"), configURL = root.appendingPathComponent("config.json"), absentURL = root.appendingPathComponent("missing.json")
        try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3])).write(to: keyURL)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
        func config(token: String = "fixture-cache-token", source: String = "standard") throws {
            let value: [String: Any] = ["appId": "fixture-cache-app", "accessToken": token, "privateKeyPath": keyURL.path, "device": ["deviceId": "fixture-cache-device"], "lyricSource": source]
            try JSONSerialization.data(withJSONObject: value).write(to: configURL)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
        }
        try config()
        let session = URLSessionConfiguration.ephemeral; session.protocolClasses = [CacheHTTP.self]
        var results: [[String: Any]] = [], current = fixtureTrack, kind = "timed"
        var now = Date(timeIntervalSince1970: 1_790_000_000)
        func check(_ name: String, _ passed: Bool) { results.append(["name": name, "passed": passed]) }
        func spin(_ done: () -> Bool, seconds: Double = 3) { let end = Date().addingTimeInterval(seconds); while !done() && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.002)) } }
        func amll() -> [String: Any] { ["status": 200, "data": ["format": "ttml", "ncmMusicIds": ["101"], "lyrics": fixtureTTML]] }
        func fixture(_ request: CacheHTTP) {
            let song: [String: Any] = ["id": 101, "name": current.title, "artists": current.artists.map { ["name": $0] }, "album": ["name": current.album], "duration": current.duration * 1000]
            switch request.request.url!.path {
            case "/api/search/get": request.send(["code": 200, "result": ["songCount": 1, "songs": [song]]])
            case "/api/song/detail": request.send(["code": 200, "songs": [song]])
            case "/api/song/lyric": request.send(["code": 200, "lrc": ["lyric": "[00:01]Public synthetic"]])
            case "/v1/lyrics/get": request.send(kind == "timed" ? amll() : [:], status: kind == "timed" ? 200 : 404)
            case "/api/get": request.send(["trackName": current.title, "artistName": current.artists.joined(separator: " / "), "albumName": current.album, "duration": current.duration, "instrumental": kind == "instrumental", "syncedLyrics": "", "plainLyrics": kind == "plain" ? "Original synthetic plain\nSecond line" : ""])
            case "/openapi/v1/ncm/cli/manifest":
                func method(_ name: String, _ path: String, _ parameter: String) -> [String: Any] { ["name": name, "path": path, "http_method": "POST", "parameters": [["name": parameter, "in": "body", "type": "string", "required": true]]] }
                request.send(["manifests": ["root": ["sub_resources": [["name": "search", "path": "s"], ["name": "song", "path": "l"]]], "s": ["methods": [method("song", "/openapi/fixture/search", "keyword")]], "l": ["methods": [method("lyric", "/openapi/fixture/lyric", "songId")]]]])
            case "/openapi/fixture/search": request.send(["code": 200, "data": ["songs": [["originalId": "101", "songId": "0123456789ABCDEF0123456789ABCDEF"]]]])
            case "/openapi/fixture/lyric", "/openapi/music/basic/song/lyric/word/by/word/get": request.send(["code": 200, "data": ["lyric": "[00:01]Official synthetic", "lrc": "[00:01]Official synthetic"]])
            default: request.send([:], status: 503)
            }
        }
        CacheHTTP.handle = fixture
        func community(_ dir: URL = directory, key: String = "ephemeral-" + stage, id: String? = nil) -> CommunityLyricOutcome? {
            let provider = CommunityLyrics(sessionConfiguration: session, cacheDirectory: dir, cacheNow: { now })
            var outcome: CommunityLyricOutcome?
            provider.load(key: key, metadata: current, neteaseID: id) { outcome = $0 }
            spin({ outcome != nil }); provider.stop(); return outcome
        }
        func legacy(_ dir: URL = directory, official: Bool = false, key: String = "ephemeral-" + stage) -> ([LyricLine], String)? {
            let provider = DesktopLyrics(sessionConfiguration: session, configurationURL: official ? configURL : absentURL, cacheDirectory: dir, cacheNow: { now })
            var outcome: ([LyricLine], String)?
            provider.load(key: key, metadata: current) { outcome = ($0, $1) }
            spin({ outcome != nil }); provider.stop(); return outcome
        }
        func files(_ dir: URL) -> [URL] { (fm.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey])?.allObjects as? [URL] ?? []).filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true } }
        func sub(_ name: String) -> URL { root.appendingPathComponent("check-" + name) }
        if stage == "seed" || stage == "hit" {
            if stage == "hit" { CacheHTTP.handle = { $0.send([:], status: 503) } }
            let timed = community()
            let line = timed?.document?.lines.first, word = line?.words.first
            check("K01 \(stage) AMLL preserves attribution, translation, timing and exact repeated-word range", timed?.document?.source == .amll && line?.text == "go go" && line?.translation == "向前" && word?.start == 3 && word?.end == 4 && word?.utf16Range == NSRange(location: 3, length: 2))
            check("K02 \(stage) public lyrics remain distinct", legacy()?.0.first?.text == "Public synthetic")
            check("K03 \(stage) official lyrics remain distinct", legacy(official: true)?.0.first?.text == "Official synthetic")
            current = TrackMetadata(title: "Plain", artists: fixtureTrack.artists, album: fixtureTrack.album, duration: 181); kind = "plain"
            check("K04 \(stage) plain LRCLIB content retained", community()?.document?.plainText == "Original synthetic plain\nSecond line")
            current = TrackMetadata(title: "Instrumental", artists: fixtureTrack.artists, album: fixtureTrack.album, duration: 182); kind = "instrumental"
            check("K04 \(stage) instrumental retained", community()?.document?.instrumental == true)
            if stage == "hit" { check("K01 process restart and new opaque keys need zero requests", CacheHTTP.requests.isEmpty) }
        } else {
            let ttl = sub("ttl"); _ = community(ttl)
            now = now.addingTimeInterval(29 * 86400); var count = CacheHTTP.requests.count
            _ = community(ttl); check("K05 unexpired cache avoids requests", CacheHTTP.requests.count == count)
            now = now.addingTimeInterval(2 * 86400); count = CacheHTTP.requests.count
            _ = community(ttl); check("K05 age is from write, not last access", CacheHTTP.requests.count > count)
            let identity = sub("identity"); _ = community(identity)
            for (label, changed) in [
                ("title version", TrackMetadata(title: "Cache Song (Live)", artists: fixtureTrack.artists, album: fixtureTrack.album, duration: 180)),
                ("artists", TrackMetadata(title: fixtureTrack.title, artists: ["Other Artist"], album: fixtureTrack.album, duration: 180)),
                ("album", TrackMetadata(title: fixtureTrack.title, artists: fixtureTrack.artists, album: "Other Album", duration: 180)),
                ("duration", TrackMetadata(title: fixtureTrack.title, artists: fixtureTrack.artists, album: fixtureTrack.album, duration: 181))
            ] {
                current = changed; count = CacheHTTP.requests.count; _ = community(identity, key: "same-opaque")
                check("K06 changed \(label) cannot reuse old cache", CacheHTTP.requests.count > count)
            }
            current = fixtureTrack; count = CacheHTTP.requests.count; _ = community(identity, id: "102")
            check("K06 trusted ID input is part of cache identity", CacheHTTP.requests.count > count)
            current = TrackMetadata(title: fixtureTrack.title, artists: [], album: fixtureTrack.album, duration: 180)
            check("K06 incomplete metadata cannot consume cache", community(identity)?.document == nil)
            current = fixtureTrack
            let broken = sub("broken"); _ = community(broken)
            for file in files(broken) { try Data("{invalid".utf8).write(to: file) }
            count = CacheHTTP.requests.count; let repaired = community(broken)
            check("K07 corrupt cache refetches successfully", repaired?.document != nil && CacheHTTP.requests.count > count)
            let unavailable = sub("not-directory"); try Data("file".utf8).write(to: unavailable)
            check("K07 unusable cache directory does not break network result", community(unavailable)?.document != nil)
            let fail = sub("failure"); CacheHTTP.handle = { $0.send([:], status: 503) }
            _ = community(fail); count = CacheHTTP.requests.count; _ = community(fail)
            check("K08 community failure is retried and not persisted", CacheHTTP.requests.count > count && files(fail).isEmpty)
            _ = legacy(fail); count = CacheHTTP.requests.count; _ = legacy(fail)
            check("K08 public failure is retried and not persisted", CacheHTTP.requests.count > count && files(fail).isEmpty)
            CacheHTTP.handle = fixture
            let scoped = sub("official"); _ = legacy(scoped, official: true)
            try config(token: "fixture-rotated-token"); count = CacheHTTP.requests.count
            _ = legacy(scoped, official: true)
            check("K09 changed official token cannot use prior account cache", CacheHTTP.requests.count > count)
            try config(token: "fixture-rotated-token", source: "word"); count = CacheHTTP.requests.count
            _ = legacy(scoped, official: true)
            check("K09 changed official lyric mode cannot use prior cache", CacheHTTP.requests.count > count)
            try Data("broken".utf8).write(to: configURL)
            check("K09 invalid official config cannot use previous success", legacy(scoped, official: true)?.0.isEmpty == true)
            count = CacheHTTP.requests.count
            check("K09 absent config selects public rather than official cache", legacy(scoped)?.0.first?.text == "Public synthetic" && CacheHTTP.requests.count > count)
            try config()
            let forbidden = ["fixture-cache-token", "fixture-rotated-token", "fixture-cache-device", "PRIVATE KEY", "manifests"]
            check("K09 cache contains no credential or manifest plaintext", files(scoped).allSatisfy { file in let text = String(decoding: (try? Data(contentsOf: file)) ?? Data(), as: UTF8.self); return forbidden.allSatisfy { !text.contains($0) } })
            let attrs = try fm.attributesOfItem(atPath: scoped.path)
            check("K10 cache directory and files have owner-only access", ((attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0o777) & 0o077 == 0 && files(scoped).allSatisfy { (((try? fm.attributesOfItem(atPath: $0.path)[.posixPermissions]) as? NSNumber)?.intValue ?? 0o777) & 0o077 == 0 })
            let clear = sub("clear"); _ = community(clear); try fm.removeItem(at: clear); count = CacheHTTP.requests.count
            _ = community(clear); check("K10 removing cache after stop forces fresh request", CacheHTTP.requests.count > count)
            let cancelled = sub("cancelled"), provider = CommunityLyrics(sessionConfiguration: session, cacheDirectory: cancelled, cacheNow: { now })
            var pending: CacheHTTP?, callback = false
            CacheHTTP.handle = { pending = $0 }
            provider.load(key: "cancel", metadata: current, neteaseID: "101") { _ in callback = true }
            spin({ pending != nil }); provider.cancel(); pending?.send(amll()); spin({ false }, seconds: 0.06)
            check("K11 cancelled response cannot callback or populate disk", !callback && files(cancelled).isEmpty)
            CacheHTTP.handle = fixture
            let cap = sub("capacity")
            for index in 0..<200 {
                current = TrackMetadata(title: "Capacity \(index)", artists: fixtureTrack.artists, album: fixtureTrack.album, duration: 180)
                now = now.addingTimeInterval(1); _ = legacy(cap)
            }
            current = TrackMetadata(title: "Capacity 0", artists: fixtureTrack.artists, album: fixtureTrack.album, duration: 180)
            now = now.addingTimeInterval(1); _ = legacy(cap)
            current = TrackMetadata(title: "Capacity 200", artists: fixtureTrack.artists, album: fixtureTrack.album, duration: 180)
            now = now.addingTimeInterval(1); _ = legacy(cap)
            count = CacheHTTP.requests.count; _ = legacy(cap)
            check("K10 newest of 201 entries remains cached", CacheHTTP.requests.count == count)
            current = TrackMetadata(title: "Capacity 0", artists: fixtureTrack.artists, album: fixtureTrack.album, duration: 180)
            count = CacheHTTP.requests.count; _ = legacy(cap)
            check("K10 recently read old entry survives LRU eviction", CacheHTTP.requests.count == count)
            current = TrackMetadata(title: "Capacity 1", artists: fixtureTrack.artists, album: fixtureTrack.album, duration: 180)
            count = CacheHTTP.requests.count; _ = legacy(cap)
            check("K10 entry count evicts oldest", CacheHTTP.requests.count > count && files(cap).count <= 200)
            check("K10 total persisted bytes stay within 20 MiB", files(cap).reduce(0) { $0 + ((try? Data(contentsOf: $1).count) ?? 0) } <= 20 * 1024 * 1024)
            let bytes = sub("bytes"), largePlain = String(repeating: "Original ", count: 55000)
            CacheHTTP.handle = { req in
                if req.request.url?.host == "lrclib.net" { req.send(["trackName": current.title, "artistName": current.artists.joined(separator: " / "), "albumName": current.album, "duration": current.duration, "instrumental": false, "syncedLyrics": "", "plainLyrics": largePlain]) }
                else if req.request.url?.host == "api.amll.dev" { req.send([:], status: 404) }
                else { fixture(req) }
            }
            for index in 0..<50 {
                current = TrackMetadata(title: "Large \(index)", artists: fixtureTrack.artists, album: fixtureTrack.album, duration: 180)
                now = now.addingTimeInterval(1); _ = community(bytes, id: "101")
            }
            count = CacheHTTP.requests.count; let largeHit = community(bytes, id: "101")
            check("K10 byte budget retains valid recent large document", largeHit?.document?.plainText == largePlain && CacheHTTP.requests.count == count)
            current = TrackMetadata(title: "Large 0", artists: fixtureTrack.artists, album: fixtureTrack.album, duration: 180)
            count = CacheHTTP.requests.count; _ = community(bytes, id: "101")
            check("K10 byte pressure evicts before count limit and respects 20 MiB", CacheHTTP.requests.count > count && files(bytes).reduce(0) { $0 + ((try? Data(contentsOf: $1).count) ?? 0) } <= 20 * 1024 * 1024)
            current = fixtureTrack
            let empty = sub("empty"); CacheHTTP.handle = { req in
                if req.request.url?.path == "/api/song/lyric" { req.send(["code": 200, "lrc": ["lyric": ""]]) }
                else { fixture(req) }
            }
            _ = legacy(empty); count = CacheHTTP.requests.count; _ = legacy(empty)
            check("K08 empty public result is not persistent success", CacheHTTP.requests.count > count && files(empty).isEmpty)
            CacheHTTP.handle = fixture
            let stable = sub("key"); _ = community(stable, key: "first-pid"); count = CacheHTTP.requests.count
            _ = community(stable, key: "second-pid")
            check("K01 changed transient player key reuses same full metadata", CacheHTTP.requests.count == count)
            check("K12 no fixture request escapes approved HTTPS sources", CacheHTTP.requests.allSatisfy { $0.url?.scheme == "https" && ["music.163.com", "api.amll.dev", "lrclib.net", "openapi.music.163.com"].contains($0.url?.host ?? "") })
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys]), as: UTF8.self))
    }
}
