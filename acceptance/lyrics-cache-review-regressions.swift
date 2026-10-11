import Foundation

private let track = TrackMetadata(title: "Review Cache", artists: ["Synthetic Artist"], album: "Synthetic Album", duration: 180)
private let ttml = "<tt xmlns=\"http://www.w3.org/ns/ttml\"><body><div><p begin=\"1\" end=\"5\"><span begin=\"2\" end=\"3\">go</span> <span begin=\"3\" end=\"4\">go</span></p></div></body></tt>"
private final class ReviewHTTP: URLProtocol {
    static var requests = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        Self.requests += 1
        let value: [String: Any] = ["status": 200, "data": ["ncmMusicIds": ["101"], "format": "ttml", "lyrics": ttml]]
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: value))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@main struct ReviewCacheRegressions {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1]), fm = FileManager.default
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ReviewHTTP.self]
        var checks: [[String: Any]] = []
        func check(_ name: String, _ pass: Bool) { checks.append(["name": name, "passed": pass]) }
        func load(_ dir: URL) -> CommunityLyricOutcome? {
            let provider = CommunityLyrics(sessionConfiguration: config, cacheDirectory: dir)
            var result: CommunityLyricOutcome?
            provider.load(key: UUID().uuidString, metadata: track, neteaseID: "101") { result = $0 }
            let deadline = Date().addingTimeInterval(3)
            while result == nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.002)) }
            provider.stop(); return result
        }
        let words = root.appendingPathComponent("words")
        let seed = load(words)
        check("R1 seed has ordered real word intervals", seed?.document?.lines.first?.words.map(\.start) == [2, 3])
        func damage(_ value: Any) -> Any {
            if var object = value as? [String: Any] {
                if var values = object["words"] as? [[String: Any]], values.count == 2 {
                    values[1]["start"] = 1.5
                    object["words"] = values
                } else { object = object.mapValues(damage) }
                return object
            }
            if let values = value as? [Any] { return values.map(damage) }
            return value
        }
        for file in try fm.contentsOfDirectory(at: words, includingPropertiesForKeys: nil) where file.pathExtension == "json" {
            let value = try JSONSerialization.jsonObject(with: Data(contentsOf: file))
            try JSONSerialization.data(withJSONObject: damage(value)).write(to: file)
        }
        let before = ReviewHTTP.requests, recovered = load(words)
        check("R1 out-of-order word cache is a network miss", ReviewHTTP.requests > before)
        check("R1 returned words come from fresh valid source", recovered?.document?.lines.first?.words.map(\.start) == [2, 3])
        let abandoned = root.appendingPathComponent("abandoned")
        try fm.createDirectory(at: abandoned, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        for _ in 0..<22 {
            let file = abandoned.appendingPathComponent("." + UUID().uuidString + ".tmp")
            try Data(repeating: 32, count: 1_048_576).write(to: file)
            try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 946684800), .posixPermissions: 0o600], ofItemAtPath: file.path)
        }
        let foreign = abandoned.appendingPathComponent("keep.txt"); try Data("unrelated".utf8).write(to: foreign)
        let fresh = load(abandoned)
        let remaining = try fm.contentsOfDirectory(at: abandoned, includingPropertiesForKeys: [.fileSizeKey])
        let bytes = remaining.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        check("R2 stale interrupted-write files cannot exceed disk budget", fresh?.document != nil && bytes <= 20 * 1_048_576)
        check("R2 cleanup preserves unrelated file", (try? String(contentsOf: foreign, encoding: .utf8)) == "unrelated")
        print(String(decoding: try JSONSerialization.data(withJSONObject: checks), as: UTF8.self))
    }
}
