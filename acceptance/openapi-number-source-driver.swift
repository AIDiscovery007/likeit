import Foundation

private final class NumberSourceProtocol: URLProtocol {
    static var mode = ""
    static var count = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.count += 1
        let json: String
        switch request.url!.path {
        case "/openapi/v1/ncm/cli/manifest":
            let extra = Self.mode == "fixed conflict" ? #",{"name":"limit","in":"body","type":"number"}"# : ""
            let fixed = Self.mode == "fixed conflict" ? #", "fixed_params":{"limit":20.0000000000000001}"# : ""
            json = #"{"manifests":{"root":{"sub_resources":[{"name":"search","path":"search"}]},"search":{"methods":[{"name":"song","path":"/openapi/fixture/search","http_method":"POST","parameters":[{"name":"keyword","in":"body","type":"string"}"# + extra + "]" + fixed + "}]}}}"
        case "/openapi/fixture/search":
            let id = Self.mode == "numeric source" ? "1377163127.0000001" : "1377163127"
            json = #"{"code":200,"data":{"songs":[{"originalId":"# + id + #", "songId":"0123456789abcdef0123456789abcdef"}]}}"#
        default: json = #"{"code":200,"data":{"lrc":"[00:01]原创"}}"#
        }
        let data = Data(json.utf8)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Length": String(data.count)])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct NumberSourceAcceptance {
    static func main() throws {
        let key = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
        let config = OpenAPILyricConfiguration(appID: "fixture-app", accessToken: "fixture-token", privateKeyPEM: key, device: ["deviceId": "fixture-device"])
        let session = URLSessionConfiguration.ephemeral; session.protocolClasses = [NumberSourceProtocol.self]
        let provider = OpenAPILyrics(configuration: config, sessionConfiguration: session)
        var checks: [[String: Any]] = []
        for mode in ["numeric source", "fixed conflict"] {
            NumberSourceProtocol.mode = mode; NumberSourceProtocol.count = 0
            var result: OpenAPILyricOutcome?
            provider.load(originalID: "1377163127", keyword: "fixture") { result = $0 }
            let deadline = Date().addingTimeInterval(3)
            while result == nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
            var passed = false
            if case .unavailable = result { passed = NumberSourceProtocol.count == (mode == "numeric source" ? 2 : 1) }
            checks.append(["name": mode, "passed": passed]); provider.cancel()
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: checks), as: UTF8.self))
    }
}
