import Foundation

private final class PersonalManifestProtocol: URLProtocol {
    static var manifest: [String: Any] = [:]
    static var mode = ""
    static var count = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.count += 1
        let body: [String: Any]
        switch request.url!.path {
        case "/openapi/v1/ncm/cli/manifest": body = Self.manifest
        case "/openapi/music/basic/search/song/get/v3":
            body = ["code": 200, "data": ["songs": [["originalId": "1377163127", "songId": "0123456789abcdef0123456789abcdef"]]]]
        case "/openapi/music/basic/song/lyric/word/by/word/get":
            body = ["code": 200, "data": Self.mode == "ordinary fallback" ? NSNull() : ["lrc": "[00:01]原创"]]
        case "/openapi/music/basic/song/lyric/get/v2":
            body = ["code": 200, "data": ["lyric": "[00:01]原创"]]
        default: body = ["code": 404]
        }
        let data = try! JSONSerialization.data(withJSONObject: body)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Length": String(data.count)])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct PersonalManifestAcceptance {
    static func main() throws {
        let key = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
        let fixture = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
        let config = OpenAPILyricConfiguration(appID: "fixture-app", accessToken: "fixture-token", privateKeyPEM: key, device: ["deviceId": "fixture-device"])
        let session = URLSessionConfiguration.ephemeral; session.protocolClasses = [PersonalManifestProtocol.self]
        let provider = OpenAPILyrics(configuration: config, sessionConfiguration: session)
        var checks: [[String: Any]] = []
        for mode in ["word original", "ordinary fallback", "malformed fixed params"] {
            PersonalManifestProtocol.mode = mode; PersonalManifestProtocol.count = 0
            var manifest = try JSONSerialization.jsonObject(with: fixture) as! [String: Any]
            if mode == "malformed fixed params" {
                var resources = manifest["manifests"] as! [String: Any]
                var search = resources["search"] as! [String: Any]
                var methods = search["methods"] as! [[String: Any]]
                methods[0]["fixed_params"] = 123
                search["methods"] = methods; resources["search"] = search; manifest["manifests"] = resources
            }
            PersonalManifestProtocol.manifest = manifest
            var result: OpenAPILyricOutcome?
            provider.load(originalID: "1377163127", keyword: "fixture") { result = $0 }
            let deadline = Date().addingTimeInterval(3)
            while result == nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
            var passed = false
            if mode == "malformed fixed params" {
                if case .unavailable = result { passed = PersonalManifestProtocol.count == 1 }
            } else if case .lines(let lines) = result {
                passed = lines.first?.text == "原创" && PersonalManifestProtocol.count == (mode == "ordinary fallback" ? 4 : 3)
            }
            checks.append(["name": mode, "passed": passed]); provider.cancel()
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: checks), as: UTF8.self))
    }
}
