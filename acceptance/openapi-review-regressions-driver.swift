import Foundation

private final class ReviewProtocol: URLProtocol {
    static var mode = ""
    static var searchCount = 0
    static var fixedValue: Any?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body: [String: Any]
        let path = request.url!.path
        if path == "/openapi/v1/ncm/cli/manifest" {
            var search: [String: Any] = ["name": "song", "path": "/openapi/fixture/search", "http_method": "POST", "auth_required": true, "parameters": [["name": "keyword", "in": "body", "type": "string", "required": true]]]
            if Self.mode.hasPrefix("fixed") {
                search["parameters"] = [["name": "keyword", "in": "body", "type": "string", "required": true], ["name": "scene", "in": "body", "type": "string", "required": true]]
                search["fixed_params"] = ["scene": Self.mode == "fixed" ? "fixture_scene" : 123]
            }
            let ordinary: [String: Any] = ["name": "lyric", "path": "/openapi/fixture/lyric", "http_method": "POST", "auth_required": true, "parameters": [["name": "songId", "in": "body", "type": "string", "required": true]]]
            body = ["manifests": ["root": ["sub_resources": [["name": "search", "path": "search"], ["name": "song", "path": "song"]]], "search": ["methods": [search]], "song": ["methods": [ordinary]]]]
        } else if path == "/openapi/fixture/search" {
            Self.searchCount += 1
            var data = request.httpBody ?? Data()
            if data.isEmpty, let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var bytes = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable { let count = stream.read(&bytes, maxLength: bytes.count); if count <= 0 { break }; data.append(contentsOf: bytes.prefix(count)) }
            }
            if let fields = try? JSONSerialization.jsonObject(with: data) as? [String: String], let business = fields["bizContent"], let object = try? JSONSerialization.jsonObject(with: Data(business.utf8)) as? [String: Any] { Self.fixedValue = object["scene"] }
            if Self.mode == "fractional" {
                send(Data(#"{"code":200,"data":{"songs":[{"originalId":1377163127.00000001,"songId":"0123456789abcdef0123456789abcdef"}]}}"#.utf8)); return
            }
            body = ["code": 200, "data": ["songs": [["originalId": "1377163127", "songId": "0123456789abcdef0123456789abcdef"]]]]
        } else if path == "/openapi/music/basic/song/lyric/word/by/word/get" {
            body = Self.mode.hasSuffix("original") ? ["code": 200, "data": NSNull()] : ["code": 200, "data": ["lrc": "[00:01]原创"]]
        } else {
            let first: Any = Self.mode == "null original" ? NSNull() : ""
            body = ["code": 200, "data": ["lyric": first, "lrc": ["lyric": "[00:01]原创"]]]
        }
        send(try! JSONSerialization.data(withJSONObject: body))
    }
    private func send(_ data: Data) {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Length": String(data.count)])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct OpenAPIReviewRegressions {
    static func main() throws {
        let key = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
        let config = OpenAPILyricConfiguration(appID: "fixture-app", accessToken: "fixture-token", privateKeyPEM: key, device: ["deviceId": "fixture-device"])
        let session = URLSessionConfiguration.ephemeral; session.protocolClasses = [ReviewProtocol.self]
        let provider = OpenAPILyrics(configuration: config, sessionConfiguration: session)
        var checks: [[String: Any]] = []
        for mode in ["fractional", "null original", "empty original", "fixed", "fixed wrong type"] {
            ReviewProtocol.mode = mode; ReviewProtocol.searchCount = 0; ReviewProtocol.fixedValue = nil
            var result: OpenAPILyricOutcome?
            provider.load(originalID: "1377163127", keyword: "fixture") { result = $0 }
            let deadline = Date().addingTimeInterval(3)
            while result == nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
            var passed = false
            if mode == "fractional" || mode == "fixed wrong type" {
                if case .unavailable = result { passed = mode != "fixed wrong type" || ReviewProtocol.searchCount == 0 }
            } else if case .lines(let lines) = result {
                passed = lines.count == 1 && lines[0].text == "原创" && (mode != "fixed" || ReviewProtocol.fixedValue as? String == "fixture_scene")
            }
            checks.append(["name": mode, "passed": passed]); provider.cancel()
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: checks), as: UTF8.self))
    }
}
