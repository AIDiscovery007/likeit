import Foundation

private final class StatusProtocol: URLProtocol {
    static var mode = ""
    static var count = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.count += 1
        let stage: String
        let body: [String: Any]
        switch request.url!.path {
        case "/openapi/v1/ncm/cli/manifest":
            stage = "manifest"
            let search: [String: Any] = ["name": "song", "path": "/openapi/fixture/search", "http_method": "POST", "parameters": [["name": "keyword", "in": "body", "type": "string"]]]
            let ordinary: [String: Any] = ["name": "lyric", "path": "/openapi/fixture/lyric", "http_method": "POST", "parameters": [["name": "songId", "in": "body", "type": "string"]]]
            body = ["code": 200, "manifests": ["root": ["sub_resources": [["name": "search", "path": "search"], ["name": "song", "path": "song"]]], "search": ["methods": [search]], "song": ["methods": [ordinary]]]]
        case "/openapi/fixture/search":
            stage = "search"
            body = ["code": 200, "data": ["songs": [["originalId": "1377163127", "songId": "0123456789abcdef0123456789abcdef"]]]]
        case "/openapi/music/basic/song/lyric/word/by/word/get":
            stage = "word"
            body = Self.mode == "ordinary" ? ["code": 200, "data": NSNull()] : ["code": 200, "data": ["lrc": "[00:01]原创"]]
        default:
            stage = "ordinary"
            body = ["code": 200, "data": ["lyric": "[00:01]原创"]]
        }
        var json = String(decoding: try! JSONSerialization.data(withJSONObject: body, options: .sortedKeys), as: UTF8.self)
        if stage == Self.mode { json = json.replacingOccurrences(of: "\"code\":200", with: "\"code\":200.00000000000001") }
        let data = Data(json.utf8)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Length": String(data.count)])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct StatusPrecisionAcceptance {
    static func main() throws {
        var checks: [[String: Any]] = []
        let raw = Data(#"{"code":200.00000000000001,"data":{"lrc":"[00:01]原创"}}"#.utf8)
        if case .malformed = decodeOpenAPIWordLyrics(raw) { checks.append(["name": "core", "passed": true]) } else { checks.append(["name": "core", "passed": false]) }
        let key = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
        let config = OpenAPILyricConfiguration(appID: "fixture-app", accessToken: "fixture-token", privateKeyPEM: key, device: ["deviceId": "fixture-device"])
        let session = URLSessionConfiguration.ephemeral; session.protocolClasses = [StatusProtocol.self]
        let provider = OpenAPILyrics(configuration: config, sessionConfiguration: session)
        for (index, stage) in ["manifest", "search", "word", "ordinary"].enumerated() {
            StatusProtocol.mode = stage; StatusProtocol.count = 0
            var result: OpenAPILyricOutcome?
            provider.load(originalID: "1377163127", keyword: "fixture") { result = $0 }
            let deadline = Date().addingTimeInterval(3)
            while result == nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
            var passed = false
            if case .unavailable = result { passed = StatusProtocol.count == index + 1 }
            checks.append(["name": stage, "passed": passed]); provider.cancel()
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: checks), as: UTF8.self))
    }
}
