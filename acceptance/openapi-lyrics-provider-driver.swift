import Foundation

private let officialHost = "openapi.music.163.com"
private let manifestPath = "/openapi/v1/ncm/cli/manifest"
private let searchPath = "/openapi/fixture/search"
private let ordinaryPath = "/openapi/fixture/lyric"
private let wordPath = "/openapi/music/basic/song/lyric/word/by/word/get"
private let encryptedID = "0123456789ABCDEF0123456789ABCDEF"
private let lyric = "[00:01.000]向前\n[00:02.200]\n[00:03.500]继续"

private final class OfflineURLProtocol: URLProtocol {
    static var handle: ((OfflineURLProtocol) -> Void)?
    static var requests: [URLRequest] = []
    static var stopped = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        DispatchQueue.main.async { Self.handle?(self) }
    }
    override func stopLoading() { Self.stopped += 1 }
    func send(_ object: Any, status: Int = 200) {
        bytes(try! JSONSerialization.data(withJSONObject: object), status: status)
    }
    func bytes(_ data: Data, status: Int = 200) {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json", "Content-Length": String(data.count)])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}

@main
struct OpenAPIProviderAcceptance {
    static func main() throws {
        let fixture = URL(fileURLWithPath: CommandLine.arguments[1])
        let directory = URL(fileURLWithPath: CommandLine.arguments[2])
        let key = try String(contentsOf: fixture.appendingPathComponent("private.pem"), encoding: .utf8)
        let keyURL = directory.appendingPathComponent("private.pem")
        let configURL = directory.appendingPathComponent("config.json")
        let absentURL = directory.appendingPathComponent("absent.json")
        try Data(key.utf8).write(to: keyURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
        let configObject: [String: Any] = ["appId": "fixture-app", "accessToken": "fixture-token", "privateKeyPath": keyURL.path, "device": ["deviceId": "fixture-device", "os": "macOS"]]
        func writeConfig(_ value: [String: Any]) throws {
            try JSONSerialization.data(withJSONObject: value).write(to: configURL)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
        }
        try writeConfig(configObject)
        let config = OpenAPILyricConfiguration(appID: "fixture-app", accessToken: "fixture-token", privateKeyPEM: key, device: ["deviceId": "fixture-device", "os": "macOS"])
        var checks: [[String: Any]] = []
        var signedRequests: [[String: Any]] = []
        func check(_ name: String, _ result: Bool) { checks.append(["name": name, "passed": result]) }
        func spin(_ until: () -> Bool, seconds: Double = 2) {
            let end = Date().addingTimeInterval(seconds)
            while !until() && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
        }
        func pause(_ seconds: Double) { spin({ false }, seconds: seconds) }
        func unavailable(_ result: OpenAPILyricOutcome?) -> Bool {
            if case .unavailable(let message) = result { return !message.isEmpty && !message.contains("fixture-secret") && !message.contains("fixture-token") && !message.contains("PRIVATE KEY") }
            return false
        }
        func hasLines(_ result: OpenAPILyricOutcome?) -> Bool {
            if case .lines(let lines) = result { return lines.count == 3 && lines[0].text == "向前" && lines[1].text.isEmpty && lines[2].time == 3.5 }
            return false
        }
        func rejectedConfiguration() -> Bool {
            do { _ = try OpenAPILyricConfiguration.load(from: configURL); return false }
            catch { return !String(describing: error).contains("fixture-token") && !String(describing: error).contains("PRIVATE KEY") }
        }
        check("missing config disables official provider", try OpenAPILyricConfiguration.load(from: absentURL) == nil)
        let loaded = try OpenAPILyricConfiguration.load(from: configURL)
        check("private config loads exact explicit values", loaded?.appID == "fixture-app" && loaded?.accessToken == "fixture-token" && loaded?.privateKeyPEM == key && loaded?.device["deviceId"] == "fixture-device")
        check("default config is outside app bundle", OpenAPILyricConfiguration.defaultURL.path == FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Likeit/netease-openapi.json").path)
        var invalid = configObject; invalid["accessToken"] = ""; try writeConfig(invalid)
        check("empty token rejected safely", rejectedConfiguration())
        invalid = configObject; invalid["device"] = [:]; try writeConfig(invalid)
        check("empty device rejected", rejectedConfiguration())
        invalid = configObject; invalid["privateKeyPath"] = "https://example.invalid/private.pem"; try writeConfig(invalid)
        check("remote key path rejected", rejectedConfiguration())
        try writeConfig(configObject)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: configURL.path)
        check("shared config permissions rejected", rejectedConfiguration())
        try writeConfig(configObject)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: keyURL.path)
        check("shared key permissions rejected", rejectedConfiguration())
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
        try Data(repeating: 32, count: 65_537).write(to: configURL)
        check("oversize config rejected", rejectedConfiguration())
        try writeConfig(configObject)

        let session = URLSessionConfiguration.ephemeral
        session.protocolClasses = [OfflineURLProtocol.self]
        let provider = OpenAPILyrics(configuration: config, sessionConfiguration: session)
        let parameter: (String, String) -> [String: Any] = { name, location in ["name": name, "in": location, "type": name == "limit" ? "integer" : "string", "required": name != "limit"] }
        func method(_ name: String, _ path: String, get: Bool = false) -> [String: Any] {
            ["name": name, "path": path, "http_method": get ? "GET" : "POST", "auth_required": true, "auth_provider": "netease", "parameters": name == "song" ? [parameter("keyword", get ? "query" : "body"), parameter("limit", get ? "query" : "body")] : [parameter("songId", "body")]]
        }
        func manifest(search: [String: Any]? = nil, ordinary: [String: Any]? = nil) -> [String: Any] {
            ["manifests": ["root": ["sub_resources": [["name": "search", "path": "search-resource"], ["name": "song", "path": "song-resource"]]], "search-resource": ["methods": [search ?? method("song", searchPath)]], "song-resource": ["methods": [ordinary ?? method("lyric", ordinaryPath)]]]]
        }
        func fields(_ request: URLRequest) -> [String: String] {
            if request.httpMethod == "GET" {
                return Dictionary(uniqueKeysWithValues: (URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            }
            if let data = request.httpBody { return (try? JSONSerialization.jsonObject(with: data)) as? [String: String] ?? [:] }
            if let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var data = Data(); var bytes = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable { let count = stream.read(&bytes, maxLength: bytes.count); if count <= 0 { break }; data.append(contentsOf: bytes.prefix(count)) }
                return (try? JSONSerialization.jsonObject(with: data)) as? [String: String] ?? [:]
            }
            return [:]
        }
        func run(manifest override: [String: Any]? = nil, songs: [[String: Any]]? = nil, word: Any? = nil, ordinary: Any? = nil, status: Int = 200) -> OpenAPILyricOutcome? {
            provider.cancel(); OfflineURLProtocol.requests = []
            OfflineURLProtocol.handle = { request in
                switch request.request.url!.path {
                case manifestPath: request.send(override ?? manifest())
                case searchPath: request.send(["code": 200, "data": ["songs": songs ?? [["originalId": "1377163127", "songId": encryptedID]]]])
                case wordPath: request.send(word ?? ["code": 200, "data": ["lrc": lyric]], status: status)
                case ordinaryPath: request.send(ordinary ?? ["code": 200, "data": ["lyric": lyric]])
                default: request.send(["code": 500, "message": "fixture-secret"])
                }
            }
            var result: OpenAPILyricOutcome?
            provider.load(originalID: "1377163127", keyword: "原创 & + / 音乐") { result = $0 }
            spin({ result != nil })
            for request in OfflineURLProtocol.requests where request.url?.host == officialHost {
                signedRequests.append(["method": request.httpMethod ?? "", "host": request.url!.host!, "path": request.url!.path, "fields": fields(request)])
            }
            return result
        }
        check("signed manifest mapping and word lyrics complete", hasLines(run()) && OfflineURLProtocol.requests.map { $0.url!.path } == [manifestPath, searchPath, wordPath])
        check("word lrc does not require ordinary lyric permission", hasLines(run(manifest: ["manifests": ["root": ["sub_resources": [["name": "search", "path": "search-resource"]]], "search-resource": ["methods": [method("song", searchPath)]]]])))
        check("manifest GET command signs query fields", hasLines(run(manifest: manifest(search: method("song", searchPath, get: true)))) && OfflineURLProtocol.requests[1].httpMethod == "GET")
        check("null word result falls back to ordinary lyrics", hasLines(run(word: ["code": 200, "data": NSNull()])) && OfflineURLProtocol.requests.last?.url?.path == ordinaryPath)
        check("unsynchronized word result uses nested ordinary lrc", hasLines(run(word: ["code": 200, "data": ["ytlrcs": lyric]], ordinary: ["code": 200, "data": ["lrc": ["lyric": lyric]]])))
        if case .noSynchronizedLyrics = run(word: ["code": 200, "data": NSNull()], ordinary: ["code": 200, "data": NSNull()]) { check("ordinary empty is not transport failure", true) } else { check("ordinary empty is not transport failure", false) }
        check("API error does not fallback or leak body", unavailable(run(word: ["code": 401, "message": "fixture-secret", "data": NSNull()])) && OfflineURLProtocol.requests.count == 3)
        check("malformed word payload does not fallback", unavailable(run(word: ["code": 200])) && OfflineURLProtocol.requests.count == 3)
        check("malformed ordinary original is not empty success", unavailable(run(word: ["code": 200, "data": NSNull()], ordinary: ["code": 200, "data": ["lyric": 123]])))
        check("HTTP failure is unavailable", unavailable(run(status: 503)) && OfflineURLProtocol.requests.count == 3)
        check("original ID is required independently", unavailable(run(songs: [["id": "1377163127", "songId": encryptedID]])) && OfflineURLProtocol.requests.count == 2)
        check("unmatched page does not guess encrypted ID", unavailable(run(songs: [["originalId": "2052348113", "songId": encryptedID]])) && OfflineURLProtocol.requests.count == 2)
        check("conflicting mappings rejected", unavailable(run(songs: [["originalId": "1377163127", "songId": encryptedID], ["originalId": "1377163127", "songId": String(repeating: "A", count: 32)]])) && OfflineURLProtocol.requests.count == 2)
        check("identical mappings may repeat", hasLines(run(songs: [["originalId": 1377163127, "encryptedId": encryptedID], ["originalId": "1377163127", "songId": encryptedID.lowercased()]])))
        check("numeric original is not encrypted ID", unavailable(run(songs: [["originalId": "1377163127", "songId": "1377163127"]])))
        for (name, change) in [
            ("off-host command rejected", ["path": "https://example.invalid/openapi/leak"] as [String: Any]),
            ("encoded traversal rejected", ["path": "/openapi/%2e%2e/leak"]),
            ("unsupported method rejected", ["http_method": "DELETE"]),
            ("unknown auth provider rejected", ["auth_provider": "other"]),
            ("undeclared keyword rejected", ["parameters": []]),
            ("upload command rejected", ["parameters": [parameter("keyword", "body"), ["name": "file", "in": "body", "type": "upload"]]]),
            ("fixed keyword cannot replace input", ["fixed_params": ["keyword": "different"]]),
            ("missing required parameter rejected", ["parameters": [parameter("keyword", "body"), parameter("unknownRequired", "body")]])
        ] {
            var descriptor = method("song", searchPath); descriptor.merge(change) { _, new in new }
            check(name, unavailable(run(manifest: manifest(search: descriptor))) && OfflineURLProtocol.requests.count == 1)
        }
        check("incomplete manifest cannot guess routes", unavailable(run(manifest: ["manifests": ["root": ["version": "1"]]])) && OfflineURLProtocol.requests.count == 1)
        OfflineURLProtocol.requests = []
        var invalidIDResult: OpenAPILyricOutcome?
        provider.load(originalID: "00000000-0000-0000-0000-000000000000", keyword: "fixture") { invalidIDResult = $0 }
        spin({ invalidIDResult != nil })
        check("MediaRemote UUID rejected before network", unavailable(invalidIDResult) && OfflineURLProtocol.requests.isEmpty)

        var pending: OfflineURLProtocol?
        OfflineURLProtocol.requests = []; OfflineURLProtocol.handle = { pending = $0 }
        var oldCallbacks = 0
        provider.load(originalID: "1377163127", keyword: "old") { _ in oldCallbacks += 1 }
        spin({ pending != nil }); provider.cancel(); pending?.send(manifest()); pause(0.15)
        check("cancel suppresses delayed callback and chain", oldCallbacks == 0 && OfflineURLProtocol.requests.count == 1)
        pending = nil; OfflineURLProtocol.handle = { pending = $0 }
        provider.load(originalID: "1377163127", keyword: "old") { _ in oldCallbacks += 1 }
        spin({ pending != nil }); let old = pending
        let replacement = run(); old?.send(manifest()); pause(0.15)
        check("new load excludes old generation", oldCallbacks == 0 && hasLines(replacement))
        OfflineURLProtocol.handle = { $0.bytes(Data(repeating: 32, count: 1_048_577)) }
        var oversized: OpenAPILyricOutcome?
        provider.load(originalID: "1377163127", keyword: "large") { oversized = $0 }
        spin({ oversized != nil }); check("oversize network response rejected", unavailable(oversized))
        provider.cancel()

        // Exercise actual DesktopLyrics wiring with a fully offline public identity chain.
        let song: [String: Any] = ["id": 1377163127, "name": "Fixture Song", "artists": [["name": "Fixture Artist"]], "album": ["name": "Fixture Album"], "duration": 180000]
        let metadata = TrackMetadata(title: "Fixture Song", artists: ["Fixture Artist"], album: "Fixture Album", duration: 180)
        func integrated(_ configurationURL: URL, ambiguous: Bool = false) -> ([LyricLine], String, [URLRequest]) {
            OfflineURLProtocol.requests = []
            OfflineURLProtocol.handle = { request in
                switch request.request.url!.path {
                case "/api/search/get": request.send(["code": 200, "result": ["songCount": ambiguous ? 101 : 1, "songs": [song]]])
                case "/api/song/detail": request.send(["code": 200, "songs": [song]])
                case "/api/song/lyric": request.send(["code": 200, "lrc": ["lyric": lyric]])
                case manifestPath: request.send(manifest())
                case searchPath: request.send(["code": 200, "data": ["songs": [["originalId": "1377163127", "songId": encryptedID]]]])
                case wordPath: request.send(["code": 200, "data": ["lrc": lyric]])
                default: request.send(["code": 500])
                }
            }
            let desktop = DesktopLyrics(sessionConfiguration: session, configurationURL: configurationURL)
            var result: ([LyricLine], String)?
            desktop.load(key: UUID().uuidString, metadata: metadata) { result = ($0, $1) }
            spin({ result != nil }); desktop.stop()
            return (result?.0 ?? [], result?.1 ?? "", OfflineURLProtocol.requests)
        }
        let unconfigured = integrated(absentURL)
        check("unconfigured desktop preserves original public chain", unconfigured.0.count == 3 && unconfigured.2.map { $0.url!.path } == ["/api/search/get", "/api/song/detail", "/api/song/lyric"])
        let configured = integrated(configURL)
        check("configured desktop verifies public identity before official lyrics", configured.0.count == 3 && configured.1.contains("歌词按歌曲信息匹配") && configured.2.map { $0.url!.path } == ["/api/search/get", "/api/song/detail", manifestPath, searchPath, wordPath])
        let ambiguous = integrated(configURL, ambiguous: true)
        check("new provider cannot bypass incomplete public identity", ambiguous.0.isEmpty && !ambiguous.2.contains { $0.url?.host == officialHost })
        try Data("invalid fixture-token JSON".utf8).write(to: configURL)
        let broken = integrated(configURL)
        check("invalid explicit config does not silently use public lyrics", broken.0.isEmpty && !broken.1.contains("fixture-token") && !broken.2.contains { $0.url?.path == "/api/song/lyric" || $0.url?.host == officialHost })
        OfflineURLProtocol.handle = nil
        let output = try JSONSerialization.data(withJSONObject: ["checks": checks, "requests": signedRequests], options: [.sortedKeys])
        print(String(decoding: output, as: UTF8.self))
    }
}
