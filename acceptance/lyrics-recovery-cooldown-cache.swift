import Foundation
private final class CooldownCacheHTTP: URLProtocol {
    static var phase = 0, official = false
    static var title = "Synthetic Song"
    static var requests: [URLRequest] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        Self.requests.append(request)
        let song: [String: Any] = ["id": 101, "name": Self.title, "artists": [["name": "Artist"]], "album": ["name": "Album"], "duration": 180000]
        let shouldLimit = Self.phase == 1 && (Self.official ? request.url?.host == "openapi.music.163.com" : request.url?.host == "music.163.com")
        var code = shouldLimit ? 429 : Self.phase == 2 ? 503 : 200
        var body: Any = ["code": code]
        if code == 200 {
            switch request.url!.path {
            case "/api/search/get": body = ["code": 200, "result": ["songCount": 1, "songs": [song]]]
            case "/api/song/detail": body = ["code": 200, "songs": [song]]
            case "/api/song/lyric": body = ["code": 200, "lrc": ["lyric": "[00:01]Synthetic cached song"]]
            case "/api/search": body = []
            case "/openapi/v1/ncm/cli/manifest":
                func method(_ name: String, _ path: String, _ param: String) -> [String: Any] { ["name": name, "path": path, "http_method": "POST", "parameters": [["name": param, "in": "body", "type": "string", "required": true]]] }
                body = ["manifests": ["root": ["sub_resources": [["name": "search", "path": "s"], ["name": "song", "path": "l"]]], "s": ["methods": [method("song", "/openapi/fixture/search", "keyword")]], "l": ["methods": [method("lyric", "/openapi/fixture/lyric", "songId")]]]]
            case "/openapi/fixture/search": body = ["code": 200, "data": ["songs": [["originalId": "101", "songId": "0123456789ABCDEF0123456789ABCDEF"]]]]
            case "/openapi/fixture/lyric": body = ["code": 200, "data": ["lyric": "[00:01]Synthetic cached song"]]
            default: code = 404; body = ["status": 404]
            }
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: code == 429 ? ["Retry-After": "60"] : nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: body)); client?.urlProtocolDidFinishLoading(self)
    }
}
@main struct CacheDuringCooldown {
    static func main() throws {
        let dir = URL(fileURLWithPath: CommandLine.arguments[1]), mode = CommandLine.arguments[2]
        CooldownCacheHTTP.official = mode == "official"
        let config = dir.appendingPathComponent("official.json"), key = dir.appendingPathComponent("fixture.pem")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3])).write(to: key)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: key.path)
        try JSONSerialization.data(withJSONObject: ["appId": "fixture-cooldown", "accessToken": "fixture-token", "device": ["deviceId": "fixture"], "privateKeyPath": key.path, "lyricSource": "standard"]).write(to: config)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: config.path)
        let url = CooldownCacheHTTP.official ? config : dir.appendingPathComponent("absent.json")
        let disk = dir.appendingPathComponent("cache"), session = URLSessionConfiguration.ephemeral
        session.protocolClasses = [CooldownCacheHTTP.self]
        func run(_ title: String) -> (Bool, String, String) {
            CooldownCacheHTTP.title = title
            let flow = DesktopLyricRecovery(lyrics: DesktopLyrics(sessionConfiguration: session, configurationURL: url, cacheDirectory: disk), community: CommunityLyrics(sessionConfiguration: session, cacheDirectory: disk), sessionConfiguration: session, configurationURL: url, cacheDirectory: disk)
            var done = false, text = "", message = ""
            flow.load(key: UUID().uuidString, metadata: TrackMetadata(title: title, artists: ["Artist"], album: "Album", duration: 180), preferredSource: "netease") { text = $0.readableText ?? ""; message = $0.message; done = true }
            let until = Date().addingTimeInterval(3)
            while !done && Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.001)) }
            flow.stop(); return (done, text, message)
        }
        var checks: [[String: Any]] = []
        let first = run("Synthetic Song")
        checks.append(["name": mode + ": exact success seeds persistent cache", "passed": first.0 && first.1.contains("Synthetic cached song") && (try? FileManager.default.contentsOfDirectory(atPath: disk.path).isEmpty) == false])
        CooldownCacheHTTP.phase = 1
        let second = run("Other Song")
        checks.append(["name": mode + ": other song triggers actual source cooldown", "passed": second.0 && LyricRequest.isCoolingDown(CooldownCacheHTTP.official ? "openapi.music.163.com" : "music.163.com")])
        CooldownCacheHTTP.phase = 2; CooldownCacheHTTP.requests = []
        let third = run("Synthetic Song")
        checks.append(["name": mode + ": cached song remains readable during cooldown", "passed": third.0 && third.1.contains("Synthetic cached song") && third.2.contains("本地缓存")])
        checks.append(["name": mode + ": cached reopen sends no requests", "passed": CooldownCacheHTTP.requests.isEmpty])
        print(String(decoding: try JSONSerialization.data(withJSONObject: checks), as: UTF8.self))
    }
}
