import Foundation

// Reviewer-owned synthetic content. Every request is intercepted; no music app access.
private let ttml = """
<tt xmlns="http://www.w3.org/ns/ttml" xmlns:ttm="http://www.w3.org/ns/ttml#metadata"><body><div>
<p begin="00:02.000" end="00:04.000"><span begin="00:02.000" end="00:03.000">Bright </span><span begin="00:03.000" end="00:04.000">day</span><span ttm:role="x-translation" xml:lang="zh-CN">晴天</span></p>
<p begin="00:05.000" end="00:07.000">Walk on</p>
</div></body></tt>
"""
private let track = TrackMetadata(title: "Synthetic Song", artists: ["Test Artist"], album: "Test Album", duration: 180)

private final class OfflineCommunityHTTP: URLProtocol {
    static var requests: [URLRequest] = []
    static var handle: ((OfflineCommunityHTTP) -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.requests.append(request); DispatchQueue.main.async { Self.handle?(self) } }
    override func stopLoading() {}
    func bytes(_ data: Data, status: Int = 200, headers: [String: String] = [:]) {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    func send(_ object: Any, status: Int = 200, headers: [String: String] = [:]) { bytes(try! JSONSerialization.data(withJSONObject: object), status: status, headers: headers) }
}

@main struct CommunityLyricsAcceptance {
    static func main() {
        var results: [[String: Any]] = []
        func check(_ name: String, _ passed: Bool) { results.append(["name": name, "passed": passed]) }
        func spin(_ condition: () -> Bool, seconds: Double = 2) { let end = Date().addingTimeInterval(seconds); while !condition() && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) } }
        let lines = parseCommunityTTML(ttml)
        check("C01 main words preserve spaces and translation", lines.count == 2 && lines.first?.text == "Bright day" && lines.first?.translation == "晴天" && lines.first?.words.map(\.text) == ["Bright ", "day"])
        check("C02 line-only remains line-only", lines.last?.text == "Walk on" && lines.last?.words.isEmpty == true)
        let bg = ttml.replacingOccurrences(of: "</p>", with: "<span ttm:role=\"x-bg\"><span begin=\"00:02.000\" end=\"00:03.000\">echo</span></span></p>")
        check("C01 background does not contaminate primary line", parseCommunityTTML(bg).first?.text == "Bright day")
        let formats = ttml.replacingOccurrences(of: "00:02.000", with: "2s").replacingOccurrences(of: "00:03.000", with: "3000ms").replacingOccurrences(of: "00:04.000", with: "00:00:04.000")
        check("C01 supported time formats are media time", parseCommunityTTML(formats).first?.words.first?.start == 2 && parseCommunityTTML(formats).first?.end == 4)
        let space = ttml.replacingOccurrences(of: ">Bright </span>", with: ">Bright</span><span begin=\"3s\" end=\"3s\"> </span>")
        check("C01 zero duration whitespace stays text not a word", parseCommunityTTML(space).first?.text == "Bright day" && parseCommunityTTML(space).first?.words.count == 2)
        for (name, bad) in [
            ("namespace", ttml.replacingOccurrences(of: "http://www.w3.org/ns/ttml\"", with: "https://wrong.invalid\"")),
            ("entity", "<!DOCTYPE tt [<!ENTITY example 'injected'>]>" + ttml),
            ("negative", ttml.replacingOccurrences(of: "00:02.000", with: "-2s")),
            ("nonfinite", ttml.replacingOccurrences(of: "00:02.000", with: "NaNs")),
            ("reversed", ttml.replacingOccurrences(of: "00:03.000", with: "00:01.000")),
            ("outside line", ttml.replacingOccurrences(of: "begin=\"00:03.000\"", with: "begin=\"00:00.000\"")),
            ("broken", String(ttml.dropLast(5))),
            ("oversize", ttml + String(repeating: " ", count: 1_048_577))
        ] { check("C03 rejects " + name, parseCommunityTTML(bad).isEmpty) }
        let word = CommunityLyricWord(start: 2, end: 4, text: "synthetic")
        check("C04 word clock clamps and seeks", communityWordProgress(word, at: 1) == 0 && communityWordProgress(word, at: 3) == 0.5 && communityWordProgress(word, at: 5) == 1 && communityWordProgress(word, at: 2.5) == 0.25)
        check("C04 invalid clock never highlights", communityWordProgress(word, at: .nan) == 0 && communityWordProgress(word, at: -.infinity) == 0 && communityWordProgress(CommunityLyricWord(start: 4, end: 2, text: "bad"), at: 3) == 0)

        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [OfflineCommunityHTTP.self]
        func amll(_ id: String = "101", lyrics: String = ttml) -> [String: Any] {
            ["status": 200, "data": ["id": 123, "filename": "synthetic.ttml", "ncmMusicIds": [id], "musicNames": [track.title], "artistNames": track.artists, "albumNames": [track.album], "lyrics": lyrics, "format": "ttml"]]
        }
        func lrclib() -> [String: Any] {
            ["id": 456, "trackName": track.title, "artistName": "Test Artist", "albumName": track.album, "duration": 180, "instrumental": false, "syncedLyrics": "[00:02.000]Synthetic line\n[00:04.000]Next line", "plainLyrics": "Synthetic line\nNext line"]
        }
        func song(id: Int = 101) -> [String: Any] { ["id": id, "name": track.title, "artists": [["name": "Test Artist"]], "album": ["name": track.album], "duration": 180000] }
        func query(_ req: URLRequest) -> [String: String] { Dictionary(uniqueKeysWithValues: (URLComponents(url: req.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") }) }
        func run(amllData: Any? = nil, amllStatus: Int = 200, lrcData: Any? = nil, lrcStatus: Int = 200, id: String? = "101", metadata: TrackMetadata = track, customize: ((OfflineCommunityHTTP) -> Bool)? = nil) -> CommunityLyricOutcome? {
            OfflineCommunityHTTP.requests = []
            let service = CommunityLyrics(sessionConfiguration: config)
            OfflineCommunityHTTP.handle = { request in
                if customize?(request) == true { return }
                switch request.request.url?.host {
                case "api.amll.dev": request.send(amllData ?? amll(), status: amllStatus)
                case "lrclib.net": request.send(lrcData ?? lrclib(), status: lrcStatus)
                case "music.163.com":
                    if request.request.url?.path == "/api/search/get" { request.send(["code": 200, "result": ["songCount": 1, "songs": [song()]]]) }
                    else { request.send(["code": 200, "songs": [song()]]) }
                default: request.send(["error": "unexpected"], status: 500)
                }
            }
            var outcome: CommunityLyricOutcome?
            service.load(key: "synthetic-key", metadata: metadata, neteaseID: id) { outcome = $0 }
            spin({ outcome != nil }); service.stop()
            return outcome
        }
        var outcome = run()
        check("C06 exact AMLL ID wins without fallback", outcome?.document?.source.rawValue == "amll" && outcome?.document?.lines.first?.translation == "晴天" && OfflineCommunityHTTP.requests.count == 1 && query(OfflineCommunityHTTP.requests[0])["ncmMusicId"] == "101")
        outcome = run(id: nil)
        check("C07 opaque snapshot uses verified search and detail", outcome?.document?.source.rawValue == "amll" && OfflineCommunityHTTP.requests.map { $0.url!.path } == ["/api/search/get", "/api/song/detail", "/v1/lyrics/get"])
        for fault in ["incomplete", "ambiguous", "detail mismatch"] {
            outcome = run(id: nil, customize: { req in
                guard req.request.url?.host == "music.163.com" else { return false }
                if req.request.url?.path == "/api/search/get" {
                    req.send(["code": 200, "result": ["songCount": fault == "incomplete" ? 100 : fault == "ambiguous" ? 2 : 1, "songs": fault == "ambiguous" ? [song(), song(id: 102)] : [song()]]])
                } else { var bad = song(); bad["name"] = "Different"; req.send(["code": 200, "songs": [bad]]) }
                return true
            })
            check("C07 " + fault + " never sends AMLL", outcome?.document?.source.rawValue == "lrclib" && !OfflineCommunityHTTP.requests.contains { $0.url?.host == "api.amll.dev" })
        }
        outcome = run(id: "media-remote-uuid")
        check("C07 invalid supplied ID never sends AMLL", outcome?.document?.source.rawValue == "lrclib" && !OfflineCommunityHTTP.requests.contains { $0.url?.host == "api.amll.dev" })
        for (name, value, status) in [
            ("404", ["status": 404] as [String: Any], 404),
            ("wrong association", amll("999"), 200),
            ("invalid TTML", amll(lyrics: "broken"), 200),
            ("error envelope", ["status": 500, "data": amll()["data"]!], 200),
            ("missing payload", ["status": 200], 200)
        ] {
            outcome = run(amllData: value, amllStatus: status)
            check("C08 fallback after " + name, outcome?.document?.source.rawValue == "lrclib" && outcome?.document?.lines.first?.text == "Synthetic line")
        }
        check("C08 LRCLIB query includes all identity fields and client", OfflineCommunityHTTP.requests.last.map { req in
            let q = query(req)
            return req.url?.path == "/api/get" && q["track_name"] == track.title && q["artist_name"] == "Test Artist" && q["album_name"] == track.album && Double(q["duration"] ?? "") == 180 && req.value(forHTTPHeaderField: "User-Agent")?.contains("Likeit") == true
        } == true)
        var plain = lrclib(); plain["syncedLyrics"] = NSNull()
        outcome = run(amllStatus: 404, lrcData: plain)
        check("C05 plain text stays unsynchronized", outcome?.document?.lines.isEmpty == true && outcome?.document?.plainText == "Synthetic line\nNext line")
        var instrumental = plain; instrumental["plainLyrics"] = NSNull(); instrumental["instrumental"] = true
        outcome = run(amllStatus: 404, lrcData: instrumental)
        check("C05 instrumental is explicit", outcome?.document?.instrumental == true && outcome?.document?.lines.isEmpty == true)
        var empty = plain; empty["plainLyrics"] = "  "
        check("C05 empty is unavailable", run(amllStatus: 404, lrcData: empty)?.document == nil)
        var contradictory = lrclib(); contradictory["instrumental"] = true
        check("C05 contradictory instrumental rejected", run(amllStatus: 404, lrcData: contradictory)?.document == nil)
        for (field, value) in [("trackName", "Synthetic Song (Live)" as Any), ("artistName", "Other" as Any), ("albumName", "Other" as Any), ("duration", 181.01 as Any), ("duration", true as Any), ("albumName", NSNull() as Any)] {
            var bad = lrclib(); bad[field] = value
            check("C09 reject " + field + " " + String(describing: value), run(amllStatus: 404, lrcData: bad)?.document == nil)
        }
        var boundary = lrclib(); boundary["duration"] = 181
        check("C09 one second boundary accepted", run(amllStatus: 404, lrcData: boundary)?.document?.source.rawValue == "lrclib")
        outcome = run(amllStatus: 503, lrcData: ["error": "remote-secret-body"], lrcStatus: 503)
        check("C10 failures remain unavailable without body leak", outcome != nil && outcome?.document == nil && outcome?.message.isEmpty == false && outcome?.message.contains("remote-secret-body") == false)
        outcome = run(amllStatus: 404, customize: { req in
            guard req.request.url?.host == "lrclib.net" else { return false }
            req.bytes(Data(repeating: 32, count: 1_048_577)); return true
        })
        check("C10 streamed oversize is rejected", outcome != nil && outcome?.document == nil)
        outcome = run(customize: { req in
            guard req.request.url?.host == "api.amll.dev" else { return false }
            req.send([:], status: 302, headers: ["Location": "https://other.invalid/lyrics"]); return true
        })
        check("C10 redirect is not followed", outcome?.document?.source.rawValue == "lrclib" && !OfflineCommunityHTTP.requests.contains { $0.url?.host == "other.invalid" })
        check("C10 all requests have fixed HTTPS and no secrets", OfflineCommunityHTTP.requests.allSatisfy { $0.url?.scheme == "https" && ["api.amll.dev", "lrclib.net", "music.163.com"].contains($0.url!.host!) && ($0.httpMethod ?? "GET") == "GET" && $0.value(forHTTPHeaderField: "Authorization") == nil && $0.value(forHTTPHeaderField: "Cookie") == nil })

        var pending: OfflineCommunityHTTP?
        let service = CommunityLyrics(sessionConfiguration: config)
        OfflineCommunityHTTP.requests = []; OfflineCommunityHTTP.handle = { pending = $0 }
        var callbacks = 0
        service.load(key: "A", metadata: track, neteaseID: "101") { _ in callbacks += 1 }
        spin({ pending != nil }); let late = pending; service.cancel(); late?.send(amll()); spin({ false }, seconds: 0.05)
        check("C13 cancel suppresses late result and chain", callbacks == 0 && OfflineCommunityHTTP.requests.count == 1)
        pending = nil; OfflineCommunityHTTP.handle = { pending = $0 }
        service.load(key: "A", metadata: track, neteaseID: "101") { _ in callbacks += 1 }
        spin({ pending != nil }); let lateA = pending
        OfflineCommunityHTTP.handle = { $0.send(amll("102")) }
        var bResult: CommunityLyricOutcome?
        service.load(key: "B", metadata: track, neteaseID: "102") { bResult = $0 }
        spin({ bResult != nil }); lateA?.send(amll()); spin({ false }, seconds: 0.05)
        check("C14 only new generation completes", callbacks == 0 && bResult?.document?.source.rawValue == "amll")
        let count = OfflineCommunityHTTP.requests.count
        var cached: CommunityLyricOutcome?
        service.load(key: "B", metadata: track, neteaseID: "102") { cached = $0 }; spin({ cached != nil })
        check("C12 successful result cached", cached?.document != nil && OfflineCommunityHTTP.requests.count == count)
        let changed = TrackMetadata(title: "Changed", artists: track.artists, album: track.album, duration: 181)
        cached = nil; service.load(key: "B", metadata: changed, neteaseID: "102") { cached = $0 }; spin({ cached != nil })
        check("C12 cache includes metadata not only opaque key", OfflineCommunityHTTP.requests.count > count)
        service.stop(); let stoppedCount = OfflineCommunityHTTP.requests.count
        cached = nil; service.load(key: "B", metadata: track, neteaseID: "102") { cached = $0 }; spin({ cached != nil })
        check("C16 stop clears memory cache", cached != nil && OfflineCommunityHTTP.requests.count > stoppedCount)
        service.stop()
        let failures = CommunityLyrics(sessionConfiguration: config)
        OfflineCommunityHTTP.requests = []; OfflineCommunityHTTP.handle = { $0.send([:], status: 503) }
        for _ in 0..<2 { var done = false; failures.load(key: "fail", metadata: track, neteaseID: "101") { _ in done = true }; spin({ done }) }
        check("C12 temporary failures are retried on explicit load", OfflineCommunityHTTP.requests.count == 4)
        failures.stop()
        let capped = CommunityLyrics(sessionConfiguration: config)
        OfflineCommunityHTTP.requests = []; OfflineCommunityHTTP.handle = { $0.send(amll(query($0.request)["ncmMusicId"] ?? "")) }
        for n in 1...21 { var done = false; capped.load(key: "key-\(n)", metadata: track, neteaseID: String(n)) { _ in done = true }; spin({ done }) }
        var evicted = false; capped.load(key: "key-1", metadata: track, neteaseID: "1") { _ in evicted = true }; spin({ evicted })
        check("C12 memory cache evicts after twenty", OfflineCommunityHTTP.requests.count == 22)
        capped.stop()
        let timeout = CommunityLyrics(sessionConfiguration: config)
        OfflineCommunityHTTP.requests = []; OfflineCommunityHTTP.handle = { _ in }
        var timeoutResult: CommunityLyricOutcome?; var timeoutCount = 0
        let began = Date()
        timeout.load(key: "timeout", metadata: track, neteaseID: "101") { timeoutResult = $0; timeoutCount += 1 }
        spin({ timeoutResult != nil }, seconds: 16.5); spin({ false }, seconds: 0.1)
        check("C11 whole load has bounded single completion", timeoutResult != nil && timeoutResult?.document == nil && timeoutCount == 1 && Date().timeIntervalSince(began) < 16.5)
        timeout.stop()
        OfflineCommunityHTTP.requests = []
        OfflineCommunityHTTP.handle = { req in
            if req.request.url?.host == "lrclib.net" { req.send([:], status: 429, headers: ["Retry-After": "60"]) }
            else { req.send([:], status: 404) }
        }
        let limited = CommunityLyrics(sessionConfiguration: config)
        for _ in 0..<2 { var done = false; limited.load(key: "limited", metadata: track, neteaseID: "101") { _ in done = true }; spin({ done }) }
        limited.stop()
        let reopened = CommunityLyrics(sessionConfiguration: config)
        var reopenedDone = false; reopened.load(key: "limited", metadata: track, neteaseID: "101") { _ in reopenedDone = true }; spin({ reopenedDone })
        check("C10 rate limit survives explicit reload and reopen", reopenedDone && OfflineCommunityHTTP.requests.filter { $0.url?.host == "lrclib.net" }.count == 1)
        reopened.stop()
        print(String(decoding: try! JSONSerialization.data(withJSONObject: results, options: [.sortedKeys]), as: UTF8.self))
    }
}
