import SwiftUI
import Foundation

@main struct HighlightRegression {
    static func main() throws {
        var results: [String: Bool] = [:]
        func check(prefix: String, word: String, name: String) {
            let xml = "<tt xmlns=\"http://www.w3.org/ns/ttml\"><body><div><p begin=\"1\" end=\"5\">\(prefix)<span begin=\"3\" end=\"4\">\(word)</span></p></div></body></tt>"
            guard let line = parseCommunityTTML(xml).first else { results[name + " parses"] = false; return }
            let before = communityHighlightedText(line, at: 2)
            let middle = communityHighlightedText(line, at: 3.5)
            func target(_ value: AttributedString) -> AttributedSubstring {
                let start = value.characters.index(value.startIndex, offsetBy: prefix.count)
                return value[start..<value.endIndex]
            }
            let firstEnd = before.characters.index(before.startIndex, offsetBy: prefix.count)
            results[name + " preserves text"] = String(before.characters) == prefix + word
            results[name + " untimed prefix unchanged"] = before[before.startIndex..<firstEnd].runs.allSatisfy { $0.foregroundColor == nil }
            results[name + " actual word waits"] = target(before).foregroundColor == Color.white.opacity(0.35)
            results[name + " actual word advances"] = target(middle).foregroundColor == Color.white.opacity(0.675)
        }
        check(prefix: "go ", word: "go", name: "duplicate")
        check(prefix: "ongoing ", word: "go", name: "substring")
        check(prefix: "向前 ", word: "向前", name: "Chinese")
        check(prefix: "🌞 go ", word: "go", name: "Unicode")
        print(String(decoding: try JSONSerialization.data(withJSONObject: results), as: UTF8.self))
    }
}
