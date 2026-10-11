import Foundation
private final class FormatHTTP: URLProtocol {
    static var rows: [[String: Any]] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        let payload: Any = request.url?.path == "/api/search" ? Self.rows : ["code": 200, "result": ["songs": [], "songCount": 0]]
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: payload)); client?.urlProtocolDidFinishLoading(self)
    }
}
@main struct FormatPriority {
    static func main() throws {
        let session = URLSessionConfiguration.ephemeral; session.protocolClasses = [FormatHTTP.self]
        let absent = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("absent.json")
        let track = TrackMetadata(title: "Synthetic Song", artists: ["Synthetic Artist"], album: "", duration: 180)
        func row(_ id: Int, _ synced: String, _ plain: String, instrumental: Bool = false, artist: String = "Synthetic Artist") -> [String: Any] {
            ["id": id, "trackName": track.title, "artistName": artist, "albumName": "Album", "duration": id == 1 ? 180 : 190, "instrumental": instrumental, "syncedLyrics": synced, "plainLyrics": plain]
        }
        let cases: [(String, [[String: Any]], String)] = [
            ("synced record beats higher-ranked plain record", [row(1, "", "Synthetic plain first"), row(2, "[00:01]Synthetic synced second", "")], "Synthetic synced second"),
            ("malformed synced record does not block valid plain", [row(1, "not a timestamp", ""), row(2, "", "Synthetic plain second")], "Synthetic plain second"),
            ("instrumental record does not hide available text", [row(1, "", "", instrumental: true), row(2, "", "Synthetic text second")], "Synthetic text second"),
            ("other-artist synced record cannot displace matching plain", [row(1, "[00:01]Wrong artist", "", artist: "Other Artist"), row(2, "", "Synthetic matching plain")], "Synthetic matching plain")
        ]
        var checks: [[String: Any]] = []
        for (name, rows, expected) in cases {
            FormatHTTP.rows = rows
            let recovery = DesktopLyricRecovery(lyrics: DesktopLyrics(sessionConfiguration: session, configurationURL: absent), community: CommunityLyrics(sessionConfiguration: session), sessionConfiguration: session, configurationURL: absent)
            var done = false, success = false
            recovery.load(key: UUID().uuidString, metadata: track, preferredSource: "netease") {
                success = $0.community?.source == .lrclib && $0.readableText?.contains(expected) == true; done = true
            }
            let end = Date().addingTimeInterval(3)
            while !done && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.001)) }
            checks.append(["name": name, "passed": done && success]); recovery.stop()
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: checks), as: UTF8.self))
    }
}
