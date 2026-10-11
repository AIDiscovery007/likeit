import Foundation
private final class ReviewHTTP: URLProtocol {
    static var requests: [URLRequest] = []
    static var duplicate = false
    static let song: [String: Any] = ["id": 101, "name": "Synthetic Song", "artists": [["name": "Artist"]], "album": ["name": "Album"], "duration": 180000]
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        Self.requests.append(request)
        var code = 200; var body: Any
        switch request.url!.path {
        case "/api/search/get": body = ["code": 200, "result": ["songCount": Self.duplicate ? 0 : 1, "songs": Self.duplicate ? [] : [Self.song]]]
        case "/api/song/detail": body = ["code": 200, "songs": [Self.song]]
        case "/openapi/v1/ncm/cli/manifest": code = 429; body = ["code": 429]
        case "/v1/lyrics/get": code = 404; body = ["status": 404]
        case "/api/search":
            body = Self.duplicate ? [
                ["id": 301, "trackName": "Synthetic Song", "artistName": "Wrong Artist", "albumName": "Album", "duration": 180, "instrumental": false, "syncedLyrics": "[00:01]WRONG RECORD", "plainLyrics": ""],
                ["id": 301, "trackName": "Synthetic Song", "artistName": "Artist", "albumName": "Album", "duration": 180, "instrumental": false, "syncedLyrics": "[00:01]CORRECT RECORD", "plainLyrics": ""]
            ] : []
        default: code = 404; body = ["code": 404]
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: code == 429 ? ["Retry-After": "60"] : nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: body)); client?.urlProtocolDidFinishLoading(self)
    }
}
@main struct ReviewRecovery {
    static func main() throws {
        let dir = URL(fileURLWithPath: CommandLine.arguments[1]), config = dir.appendingPathComponent("official.json"), key = dir.appendingPathComponent("fixture.pem")
        try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])).write(to: key)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: key.path)
        try JSONSerialization.data(withJSONObject: ["appId": "fixture-review", "accessToken": "fixture-token", "device": ["deviceId": "fixture"], "privateKeyPath": key.path, "lyricSource": "standard"]).write(to: config)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: config.path)
        let session = URLSessionConfiguration.ephemeral; session.protocolClasses = [ReviewHTTP.self]
        var checks: [[String: Any]] = []
        let track = TrackMetadata(title: "Synthetic Song", artists: ["Artist"], album: "Album", duration: 180)
        func run(_ metadata: TrackMetadata, url: URL) -> (Bool, String) {
            let flow = DesktopLyricRecovery(lyrics: DesktopLyrics(sessionConfiguration: session, configurationURL: url), community: CommunityLyrics(sessionConfiguration: session), sessionConfiguration: session, configurationURL: url)
            var done = false, text = ""
            flow.load(key: UUID().uuidString, metadata: metadata, preferredSource: "netease") { text = $0.readableText ?? ""; done = true }
            let until = Date().addingTimeInterval(3)
            while !done && Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.001)) }
            flow.stop(); return (done, text)
        }
        let first = run(track, url: config)
        let count = ReviewHTTP.requests.filter { $0.url?.host == "openapi.music.163.com" }.count
        checks.append(["name": "official 429 was actually observed", "passed": first.0 && count > 0])
        let second = run(track, url: config)
        checks.append(["name": "reopen respects official cooldown before exact provider", "passed": second.0 && ReviewHTTP.requests.filter { $0.url?.host == "openapi.music.163.com" }.count == count])
        ReviewHTTP.duplicate = true
        let third = run(TrackMetadata(title: track.title, artists: track.artists, album: "", duration: 0), url: dir.appendingPathComponent("absent.json"))
        checks.append(["name": "duplicate ID keeps lyrics bound to the matched record", "passed": third.0 && third.1.contains("CORRECT RECORD") && !third.1.contains("WRONG RECORD")])
        print(String(decoding: try JSONSerialization.data(withJSONObject: checks), as: UTF8.self))
    }
}
