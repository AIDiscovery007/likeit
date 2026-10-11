import Foundation

private final class RecoveryHTTP: URLProtocol {
    static var requests: [URLRequest] = []
    static var reply: ((URLRequest) -> (Int, Any))!
    static var delay = 0.0
    private var stopped = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() { stopped = true }
    override func startLoading() {
        Self.requests.append(request)
        let (status, body) = Self.reply(request)
        let data = try! JSONSerialization.data(withJSONObject: body)
        let deliver = { [self] in
            guard !stopped else { return }
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
        if Self.delay > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + Self.delay, execute: deliver) }
        else { deliver() }
    }
}

@main struct RecoveryAcceptance {
    static func main() throws {
        let stage = CommandLine.arguments[1], dir = URL(fileURLWithPath: CommandLine.arguments[2])
        let fm = FileManager.default, key = dir.appendingPathComponent("fixture.pem"), config = dir.appendingPathComponent("official.json")
        try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3])).write(to: key)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: key.path)
        try JSONSerialization.data(withJSONObject: ["appId": "fixture-recovery", "accessToken": "fixture-token", "device": ["deviceId": "fixture"], "privateKeyPath": key.path, "lyricSource": "standard"]).write(to: config)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: config.path)
        let absent = dir.appendingPathComponent("absent.json"), session = URLSessionConfiguration.ephemeral
        session.protocolClasses = [RecoveryHTTP.self]
        let metadata = TrackMetadata(title: "Café Song", artists: ["Artist A"], album: "Album", duration: 180)
        let good: [String: Any] = ["id": 101, "name": "Café Song", "artists": [["name": "Artist A"]], "album": ["name": "Album"], "duration": 180000]
        func song(_ change: [String: Any]) -> [String: Any] { good.merging(change) { _, b in b } }
        func lrclib(plain: Bool = false) -> [String: Any] {
            ["id": 301, "trackName": "Café Song", "artistName": "Artist A", "albumName": "Other Album", "duration": 190, "instrumental": false, "syncedLyrics": plain ? "" : "[00:01]Synthetic LRCLIB", "plainLyrics": "Synthetic plain LRCLIB"]
        }
        struct Scenario {
            var name: String
            var track: TrackMetadata
            var songs: [[String: Any]]
            var total: Int? = nil
            var official = false
            var invalidConfig = false
            var officialFails = false
            var publicAvailable: Set<Int> = [101, 202]
            var amll = true
            var lrclib: [[String: Any]] = []
            var detail: [String: Any]? = nil
            var expected: String? = "Synthetic public 101"
            var source = "网易"
            var noRequests = false
            var serial = true
        }
        var scenarios: [Scenario] = []
        func add(_ name: String, _ change: (inout Scenario) -> Void = { _ in }) {
            var s = Scenario(name: name, track: metadata, songs: [good]); change(&s); scenarios.append(s)
        }
        let junk = song(["id": 999, "name": "Unrelated Mashup", "album": ["name": ""]])
        add("public lyrics survive unrelated malformed record") { $0.songs = [junk, good] }
        add("official lyrics survive unrelated malformed record") { $0.songs = [junk, good]; $0.official = true; $0.expected = "Synthetic official" }
        add("unknown record does not poison usable candidate") { $0.songs = [["id": 999], good] }
        add("partial search can provide a candidate") { $0.total = 500 }
        add("missing current album") { $0.track = TrackMetadata(title: metadata.title, artists: metadata.artists, album: "", duration: 180) }
        add("missing current duration") { $0.track = TrackMetadata(title: metadata.title, artists: metadata.artists, album: metadata.album, duration: 0) }
        add("missing current artist") { $0.track = TrackMetadata(title: metadata.title, artists: [], album: metadata.album, duration: 180) }
        add("all optional metadata missing") { $0.track = TrackMetadata(title: metadata.title, artists: [], album: "", duration: 0) }
        add("candidate album differs") { $0.songs = [song(["album": ["name": "Other"]])] ; $0.detail = $0.songs[0] }
        add("candidate duration differs") { $0.songs = [song(["duration": 195000])]; $0.detail = $0.songs[0] }
        add("candidate auxiliary fields missing") { $0.songs = [song(["album": ["name": ""], "duration": NSNull()])]; $0.detail = $0.songs[0] }
        add("album and duration rank the original first") { $0.songs = [song(["id": 202, "album": ["name": "Other"], "duration": 195000]), good] }
        add("same-rank duplicates do not block lyrics") { $0.songs = [song(["id": 202]), good] }
        add("next Netease candidate used before community") { $0.songs = [good, song(["id": 202, "album": ["name": "Other"]])]; $0.publicAvailable = [202]; $0.expected = "Synthetic public 202" }
        add("Netease failure goes to AMLL") { $0.publicAvailable = []; $0.expected = "Synthetic AMLL"; $0.source = "AMLL" }
        add("official authentication failure goes to AMLL without public bypass") { $0.official = true; $0.officialFails = true; $0.expected = "Synthetic AMLL"; $0.source = "AMLL" }
        add("invalid official config goes to AMLL without public bypass") { $0.invalidConfig = true; $0.expected = "Synthetic AMLL"; $0.source = "AMLL" }
        add("Netease and AMLL failure goes to LRCLIB") { $0.publicAvailable = []; $0.amll = false; $0.lrclib = [lrclib()]; $0.expected = "Synthetic LRCLIB"; $0.source = "LRCLIB" }
        add("LRCLIB plain text remains readable") { $0.publicAvailable = []; $0.amll = false; $0.lrclib = [lrclib(plain: true)]; $0.expected = "Synthetic plain LRCLIB"; $0.source = "LRCLIB" }
        add("no Netease ID still reaches LRCLIB") { $0.songs = []; $0.amll = false; $0.lrclib = [lrclib()]; $0.expected = "Synthetic LRCLIB"; $0.source = "LRCLIB" }
        add("title-only LRCLIB lookup") { $0.track = TrackMetadata(title: metadata.title, artists: [], album: "", duration: 0); $0.songs = []; $0.lrclib = [lrclib()]; $0.expected = "Synthetic LRCLIB"; $0.source = "LRCLIB" }
        add("LRCLIB optional response fields may be null") { $0.publicAvailable = []; $0.amll = false; var row = lrclib(); row["albumName"] = NSNull(); row["duration"] = NSNull(); $0.lrclib = [row]; $0.expected = "Synthetic LRCLIB"; $0.source = "LRCLIB" }
        add("known different artist not displayed") { $0.songs = [song(["artists": [["name": "Other Artist"]]])]; $0.expected = nil; $0.amll = false }
        add("different title not displayed") { $0.songs = [song(["name": "Other Song"])]; $0.expected = nil; $0.amll = false }
        add("live version not silently stripped") { $0.songs = [song(["name": "Café Song (Live)"])]; $0.expected = nil; $0.amll = false }
        add("detail title mismatch cannot supply Netease or AMLL identity") { $0.detail = song(["name": "Other Song"]); $0.expected = nil; $0.amll = false }
        add("all channels missing gives honest final message") { $0.publicAvailable = []; $0.amll = false; $0.expected = nil }
        add("blank title makes no network request") { $0.track = TrackMetadata(title: "  ", artists: [], album: "", duration: 0); $0.noRequests = true; $0.expected = nil }
        add("Unicode canonical title still matches") { $0.track = TrackMetadata(title: " CAFE\u{301}   SONG ", artists: metadata.artists, album: "", duration: 0) }

        func configure(_ s: Scenario) {
            RecoveryHTTP.requests = []
            RecoveryHTTP.reply = { req in
                let path = req.url!.path
                let query = Dictionary(uniqueKeysWithValues: (URLComponents(url: req.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
                switch path {
                case "/api/search/get": return (200, ["code": 200, "result": ["songCount": s.total ?? s.songs.count, "songs": s.songs]])
                case "/api/song/detail":
                    let id = Int((query["ids"] ?? "").filter(\.isNumber)) ?? 101
                    return (200, ["code": 200, "songs": [s.detail ?? s.songs.first(where: { ($0["id"] as? Int) == id }) ?? good]])
                case "/api/song/lyric":
                    let id = Int(query["id"] ?? "") ?? 0
                    return (200, ["code": 200, "lrc": ["lyric": s.publicAvailable.contains(id) ? "[00:01]Synthetic public \(id)" : ""]])
                case "/v1/lyrics/get":
                    return (s.amll ? 200 : 404, ["status": s.amll ? 200 : 404, "data": ["format": "ttml", "ncmMusicIds": [query["ncmMusicId"] ?? ""], "lyrics": "<tt xmlns=\"http://www.w3.org/ns/ttml\"><body><div><p begin=\"1\" end=\"3\">Synthetic AMLL</p></div></body></tt>"]])
                case "/api/search": return (200, s.lrclib)
                case "/api/get": return (404, ["code": 404])
                case "/openapi/v1/ncm/cli/manifest":
                    func method(_ name: String, _ path: String, _ param: String) -> [String: Any] { ["name": name, "path": path, "http_method": "POST", "parameters": [["name": param, "in": "body", "type": "string", "required": true]]] }
                    return (200, ["manifests": ["root": ["sub_resources": [["name": "search", "path": "s"], ["name": "song", "path": "l"]]], "s": ["methods": [method("song", "/openapi/fixture/search", "keyword")]], "l": ["methods": [method("lyric", "/openapi/fixture/lyric", "songId")]]]])
                case "/openapi/fixture/search": return (200, ["code": 200, "data": ["songs": [["originalId": "101", "songId": "0123456789ABCDEF0123456789ABCDEF"]]]])
                case "/openapi/fixture/lyric": return (s.officialFails ? 401 : 200, ["code": s.officialFails ? 401 : 200, "data": ["lyric": "[00:01]Synthetic official"]])
                default: return (404, ["code": 404])
                }
            }
        }
        let bad = dir.appendingPathComponent("bad.json"); try Data("invalid".utf8).write(to: bad)
        func make(_ s: Scenario, disk: URL? = nil) -> DesktopLyricRecovery {
            let url = s.invalidConfig ? bad : s.official ? config : absent
            return DesktopLyricRecovery(lyrics: DesktopLyrics(sessionConfiguration: session, configurationURL: url, cacheDirectory: disk), community: CommunityLyrics(sessionConfiguration: session, cacheDirectory: disk), sessionConfiguration: session, configurationURL: url, cacheDirectory: disk)
        }
        func wait(_ seconds: Double = 3, until done: () -> Bool) {
            let end = Date().addingTimeInterval(seconds)
            while !done() && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.001)) }
        }
        var checks: [[String: Any]] = []
        func check(_ name: String, _ value: Bool) { checks.append(["name": name, "passed": value]) }
        if stage == "checks" {
            for s in scenarios {
                configure(s); let recovery = make(s)
                var done = false, text: String?, message = ""
                recovery.load(key: UUID().uuidString, metadata: s.track, preferredSource: "netease") { result in
                    text = result.readableText; message = result.message; done = true
                }
                wait(until: { done })
                let paths = RecoveryHTTP.requests.map { $0.url!.path }
                let channels = paths.compactMap { path -> Int? in
                    if ["/api/song/lyric", "/openapi/fixture/lyric"].contains(path) { return 0 }
                    if path == "/v1/lyrics/get" { return 1 }
                    if path == "/api/search" { return 2 }
                    return nil
                }
                let ordered = zip(channels, channels.dropFirst()).allSatisfy { $0 <= $1 }
                let lastSource = s.source == "网易" ? 0 : s.source == "AMLL" ? 1 : 2
                let contentOK = s.expected.map { text?.contains($0) == true && message.contains(s.source) && channels.allSatisfy { $0 <= lastSource } } ?? ((text ?? "").isEmpty && message.contains("暂时没有匹配的歌词"))
                let noBypass = !(s.official || s.invalidConfig) || !paths.contains("/api/song/lyric")
                let requestOK = RecoveryHTTP.requests.filter { $0.url?.host == "lrclib.net" && $0.url?.path == "/api/search" }.allSatisfy { req in
                    let q = URLComponents(url: req.url!, resolvingAgainstBaseURL: false)!.queryItems ?? []
                    return q.contains { $0.name == "track_name" } && !q.contains { ["album_name", "duration"].contains($0.name) }
                }
                check(s.name, done && contentOK && ordered && noBypass && requestOK && (!s.noRequests || paths.isEmpty))
                recovery.stop()
            }
            var raw: [String: Any] = ["bundleIdentifier": "com.netease.163music", "processIdentifier": 123, "playing": true, "title": "Café Song"]
            check("verified title-only snapshot accepted", DesktopSnapshot(raw, expectedPID: 123)?.metadata.title == "Café Song")
            check("unknown duration does not fabricate elapsed clock", DesktopSnapshot(raw, expectedPID: 123)?.metadata.duration == 0 && DesktopSnapshot(raw, expectedPID: 123)?.elapsed == nil)
            raw["artist"] = "Artist A"; raw["album"] = ""; raw["durationMicros"] = 180000000
            check("missing album and content ID accepted", DesktopSnapshot(raw, expectedPID: 123)?.metadata.artists == ["Artist A"])
            check("foreign process rejected", DesktopSnapshot(raw, expectedPID: 456) == nil)
            raw["bundleIdentifier"] = "other"
            check("foreign bundle rejected", DesktopSnapshot(raw, expectedPID: 123) == nil)
            raw["bundleIdentifier"] = "com.netease.163music"; raw["title"] = " "
            check("blank snapshot title rejected", DesktopSnapshot(raw, expectedPID: 123) == nil)
            let s = scenarios[0]; configure(s); RecoveryHTTP.delay = 0.05; let recovery = make(s)
            var stale = false, current = false
            recovery.load(key: "old", metadata: metadata, preferredSource: "netease") { _ in stale = true }
            recovery.cancel()
            RecoveryHTTP.delay = 0
            recovery.load(key: "new", metadata: metadata, preferredSource: "netease") { current = $0.readableText?.contains("Synthetic public 101") == true }
            wait(until: { current }); RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            check("cancelled old completion cannot replace current song", !stale && current); recovery.stop()
        } else {
            var s = scenarios[7]; s.publicAvailable = []; s.amll = false; s.lrclib = [lrclib()]; s.expected = "Synthetic LRCLIB"
            configure(s)
            if stage == "hit" { RecoveryHTTP.reply = { _ in (503, ["error": "offline"]) } }
            let recovery = make(s, disk: dir.appendingPathComponent("cache")); var done = false, text: String?, message = ""
            recovery.load(key: UUID().uuidString, metadata: s.track, preferredSource: "netease") { text = $0.readableText; message = $0.message; done = true }
            wait(until: { done })
            check(stage + ": partial metadata success persists across real processes", done && text?.contains("Synthetic LRCLIB") == true)
            check(stage + ": cache precedes all matching requests", stage == "seed" ? !RecoveryHTTP.requests.isEmpty : RecoveryHTTP.requests.isEmpty && message.contains("本地缓存"))
            recovery.stop()
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: checks), as: UTF8.self))
    }
}
