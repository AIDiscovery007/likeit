import Foundation

private final class WireProtocol: URLProtocol {
    static var searchURL = ""
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let body: [String: Any]
        switch request.url!.path {
        case "/openapi/v1/ncm/cli/manifest":
            body = ["manifests": ["root": ["sub_resources": [["name": "search", "path": "search-resource"]]], "search-resource": ["methods": [["name": "song", "path": "/openapi/fixture/search", "http_method": "GET", "auth_required": true, "parameters": [["name": "keyword", "in": "query", "type": "string", "required": true], ["name": "limit", "in": "query", "type": "integer"]]]]]]]
        case "/openapi/fixture/search":
            Self.searchURL = request.url!.absoluteString
            body = ["code": 200, "data": ["songs": [["originalId": "1377163127", "songId": "0123456789abcdef0123456789abcdef"]]]]
        default: body = ["code": 200, "data": ["lrc": "[00:01]原创"]]
        }
        let data = try! JSONSerialization.data(withJSONObject: body)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Length": String(data.count)])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct OpenAPIGetWireAcceptance {
    static func main() throws {
        let key = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
        let config = OpenAPILyricConfiguration(appID: "fixture-app", accessToken: "fixture+token", privateKeyPEM: key, device: ["deviceId": "fixture+device/A & B"])
        let session = URLSessionConfiguration.ephemeral
        session.protocolClasses = [WireProtocol.self]
        let provider = OpenAPILyrics(configuration: config, sessionConfiguration: session)
        var done = false
        provider.load(originalID: "1377163127", keyword: "原创 & + / 音乐") { _ in done = true }
        let deadline = Date().addingTimeInterval(3)
        while !done && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
        provider.cancel()
        print(WireProtocol.searchURL)
    }
}
