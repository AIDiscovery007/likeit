import Foundation

final class FixtureProtocol: URLProtocol {
    static var scenario = ""
    static var requests: [String] = []
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "music.163.com" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.path
        Self.requests.append(path)
        let valid: [String: Any] = ["id":123,"name":"Fixture Song","artists":[["name":"Artist"]],"album":["name":"Album"],"duration":180000]
        var result: [String: Any] = ["code":200]
        if path == "/api/search/get" {
            var other = valid
            other["id"] = 124
            switch Self.scenario {
            case "blank-title": other["name"] = "  "
            case "blank-album": other["album"] = ["name":"\t"]
            case "blank-artist": other["artists"] = [["name":"\n"]]
            case "missing-artist": other["artists"] = [["id":99]]
            default: break
            }
            let songs = Self.scenario == "valid" ? [valid] : [valid, other]
            result["result"] = ["songCount": songs.count, "songs": songs]
        } else if path == "/api/song/detail" { result["songs"] = [valid] }
        else { result["lrc"] = ["lyric":"[00:00]Synthetic fixture\n[00:01]Second line"] }
        let data = try! JSONSerialization.data(withJSONObject: result)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type":"application/json", "Content-Length":String(data.count)])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct Probe {
    static func main() {
        URLProtocol.registerClass(FixtureProtocol.self)
        var results: [[String: Any]] = []
        for name in ["valid", "blank-title", "blank-album", "blank-artist", "missing-artist"] {
            FixtureProtocol.scenario = name; FixtureProtocol.requests = []
            let lyrics = DesktopLyrics()
            var received: Int?
            lyrics.load(key: name, metadata: TrackMetadata(title:"Fixture Song", artists:["Artist"], album:"Album", duration:180)) { lines, _ in received = lines.count }
            let end = Date().addingTimeInterval(6)
            while received == nil && Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
            lyrics.stop()
            results.append(["case": name, "lines": received as Any? ?? NSNull(), "requests": FixtureProtocol.requests,
                            "passed": name == "valid" ? received == 2 && FixtureProtocol.requests.count == 3 : received == 0 && FixtureProtocol.requests == ["/api/search/get"]])
        }
        let bytes = try! JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted,.sortedKeys])
        print(String(decoding: bytes, as: UTF8.self))
    }
}
