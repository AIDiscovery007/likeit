import Foundation

@main struct CommunityLyricsReviewRegressions {
    static func main() throws {
        let line = "<p begin=\"2s\" end=\"4s\"><span begin=\"2s\" end=\"3s\">Clear </span><span begin=\"3s\" end=\"4s\">sky</span></p>"
        func document(_ container: String, body: String = "") -> String {
            "<tt xmlns=\"http://www.w3.org/ns/ttml\"><body \(body)>\(container)</body></tt>"
        }
        let container = "<div begin=\"2s\" end=\"4s\">\(line)</div>"
        let parsed = parseCommunityTTML(document(container))
        let results: [String: Bool] = [
            "timed div preserves absolute line and word times": parsed.count == 1 && parsed.first?.start == 2 && parsed.first?.words.first?.start == 2 && parsed.first?.text == "Clear sky",
            "timed body and nested div are supported": parseCommunityTTML(document("<div>\(container)</div>", body: "begin=\"0s\" end=\"5s\"")).count == 1,
            "reversed container rejected": parseCommunityTTML(document("<div begin=\"4s\" end=\"2s\">\(line)</div>")).isEmpty,
            "negative container rejected": parseCommunityTTML(document("<div begin=\"-1s\" end=\"4s\">\(line)</div>")).isEmpty,
            "partial container time rejected": parseCommunityTTML(document("<div begin=\"2s\">\(line)</div>")).isEmpty,
            "line outside bounded ancestor rejected": parseCommunityTTML(document("<div begin=\"3s\" end=\"4s\"><div>\(line)</div></div>")).isEmpty
        ]
        print(String(decoding: try JSONSerialization.data(withJSONObject: results), as: UTF8.self))
    }
}
