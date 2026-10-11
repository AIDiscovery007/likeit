import Foundation

private final class PersonalFlowProtocol: URLProtocol {
    static var manifest: [String: Any] = [:]
    static var mode = ""
    static var paths: [String] = []
    static var business: [String: Any] = [:]
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.path
        Self.paths.append(path)
        let body: [String: Any]
        switch path {
        case "/openapi/v1/ncm/cli/manifest": body = Self.manifest
        case "/openapi/music/basic/search/song/get/v3":
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            let value = query.first { $0.name == "bizContent" }!.value!
            Self.business = try! JSONSerialization.jsonObject(with: Data(value.utf8)) as! [String: Any]
            let id = "0123456789abcdef0123456789abcdef"
            var row: [String: Any] = ["originalId": 1377163127]
            let records = Self.mode.hasPrefix("records")
            row[records ? "id" : "songId"] = id
            if Self.mode == "records missing original" { row.removeValue(forKey: "originalId") }
            if Self.mode == "records numeric id" { row["id"] = 1377163127 }
            if Self.mode == "records conflicting id" { row["songId"] = String(repeating: "A", count: 32) }
            body = ["code": 200, "data": [records ? "records" : "songs": [row]]]
        case "/openapi/music/basic/song/lyric/word/by/word/get":
            body = Self.mode.hasPrefix("standard") || Self.mode == "word permission error" ? ["code": 300] : ["code": 200, "data": ["lrc": "[00:01]原创"]]
        case "/openapi/music/basic/song/lyric/get/v2":
            body = Self.mode == "standard permission error" ? ["code": 300] : ["code": 200, "data": ["lyric": "[00:01]原创"]]
        default: body = ["code": 404]
        }
        let data = try! JSONSerialization.data(withJSONObject: body)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Length": String(data.count)])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct PersonalFlowAcceptance {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let keyURL = directory.appendingPathComponent("private.pem"), configURL = directory.appendingPathComponent("config.json")
        try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])).write(to: keyURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
        let fixture = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
        func configuration(_ source: Any) throws -> OpenAPILyricConfiguration {
            let json: [String: Any] = ["appId": "fixture-app", "accessToken": "fixture-token", "privateKeyPath": keyURL.path, "device": ["deviceId": "fixture-device"], "lyricSource": source]
            try JSONSerialization.data(withJSONObject: json).write(to: configURL)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
            return try OpenAPILyricConfiguration.load(from: configURL)!
        }
        var checks: [[String: Any]] = []
        for mode in ["defaults", "provided wins", "invalid used default", "records pair", "records missing original", "records numeric id", "records conflicting id", "standard", "standard permission error", "word permission error"] {
            var manifest = try JSONSerialization.jsonObject(with: fixture) as! [String: Any]
            if mode == "provided wins" || mode == "invalid used default" {
                var resources = manifest["manifests"] as! [String: Any], search = (manifest["manifests"] as! [String: Any])["search"] as! [String: Any]
                var methods = search["methods"] as! [[String: Any]], parameters = (search["methods"] as! [[String: Any]])[0]["parameters"] as! [[String: Any]]
                let name = mode == "provided wins" ? "keyword" : "offset"
                let index = parameters.firstIndex { $0["name"] as? String == name }!
                parameters[index]["default"] = mode == "provided wins" ? "wrong default" : "not a number"
                methods[0]["parameters"] = parameters; search["methods"] = methods; resources["search"] = search; manifest["manifests"] = resources
            }
            PersonalFlowProtocol.manifest = manifest; PersonalFlowProtocol.mode = mode
            PersonalFlowProtocol.paths = []; PersonalFlowProtocol.business = [:]
            let config = try configuration(mode.hasPrefix("standard") ? "standard" : "word")
            let session = URLSessionConfiguration.ephemeral; session.protocolClasses = [PersonalFlowProtocol.self]
            let provider = OpenAPILyrics(configuration: config, sessionConfiguration: session)
            var result: OpenAPILyricOutcome?
            provider.load(originalID: "1377163127", keyword: "fixture") { result = $0 }
            let deadline = Date().addingTimeInterval(3)
            while result == nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
            let paths = PersonalFlowProtocol.paths
            let expectedSuccess = ["defaults", "provided wins", "records pair", "standard"].contains(mode)
            var passed = false
            if expectedSuccess, case .lines(let lines) = result { passed = lines.first?.text == "原创" && paths.count == 3 }
            if !expectedSuccess, case .unavailable = result { passed = true }
            if mode == "invalid used default" { passed = passed && paths.count == 1 }
            if mode.hasPrefix("records"), mode != "records pair" { passed = passed && paths.count == 2 }
            if mode.hasPrefix("standard") { passed = passed && paths.last == "/openapi/music/basic/song/lyric/get/v2" && paths.count == 3 }
            if mode == "word permission error" { passed = passed && paths.last == "/openapi/music/basic/song/lyric/word/by/word/get" && paths.count == 3 }
            checks.append(["name": mode, "passed": passed, "business": PersonalFlowProtocol.business]); provider.cancel()
        }
        var invalidRejected = true
        for value: Any in ["unsupported", NSNull(), 123] {
            do { _ = try configuration(value); invalidRejected = false } catch {}
        }
        checks.append(["name": "invalid explicit source rejected", "passed": invalidRejected])
        print(String(decoding: try JSONSerialization.data(withJSONObject: checks), as: UTF8.self))
    }
}
