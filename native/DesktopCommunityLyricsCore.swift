import Foundation

struct CommunityLyricWord {
    let start: Double
    let end: Double
    let text: String
    let utf16Range: NSRange?

    init(start: Double, end: Double, text: String, utf16Range: NSRange? = nil) {
        self.start = start; self.end = end; self.text = text; self.utf16Range = utf16Range
    }
}
struct CommunityLyricLine { let start: Double; let end: Double; let text: String; let translation: String?; let words: [CommunityLyricWord] }
enum CommunityLyricSource: String { case amll, lrclib }
struct CommunityLyricDocument { let source: CommunityLyricSource; let lines: [CommunityLyricLine]; let plainText: String?; let instrumental: Bool }
struct CommunityLyricOutcome { let document: CommunityLyricDocument?; let message: String }

func communityWordProgress(_ word: CommunityLyricWord, at position: Double) -> Double {
    guard [word.start, word.end, position].allSatisfy(\.isFinite), word.start >= 0, word.end > word.start, position >= 0 else { return 0 }
    return min(1, max(0, (position - word.start) / (word.end - word.start)))
}

private let ttmlNamespace = "http://www.w3.org/ns/ttml"
private let metadataNamespace = "http://www.w3.org/ns/ttml#metadata"

private func communityTime(_ text: String) -> Double? {
    guard text.range(of: #"^(?:[0-9]+:)?[0-9]+:[0-5][0-9](?:\.[0-9]+)?$|^[0-9]+(?:\.[0-9]+)?(?:ms|s)?$"#, options: .regularExpression) != nil else { return nil }
    let value: Double?
    if text.hasSuffix("ms") { value = Double(text.dropLast(2)).map { $0 / 1000 } }
    else if text.hasSuffix("s") { value = Double(text.dropLast()) }
    else {
        let parts = text.split(separator: ":")
        if parts.count == 3 && (Double(parts[1]) ?? 60) >= 60 { return nil }
        value = parts.reduce(0.0) { $0 * 60 + (Double($1) ?? .nan) }
    }
    return value.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
}

private final class TTMLNode {
    enum Content { case text(String), node(TTMLNode) }
    let name: String
    let namespace: String?
    let attributes: [String: String]
    let role: String?
    let language: String?
    var content: [Content] = []
    init(name: String, namespace: String?, attributes: [String: String], role: String?, language: String?) {
        self.name = name; self.namespace = namespace; self.attributes = attributes; self.role = role; self.language = language
    }
    var text: String { content.map { part in switch part { case .text(let text): return text; case .node(let node): return node.text } }.joined() }
    var children: [TTMLNode] { content.compactMap { if case .node(let node) = $0 { return node }; return nil } }
}

private final class CommunityTTMLParser: NSObject, XMLParserDelegate {
    var root: TTMLNode?
    var invalid = false
    private var stack: [TTMLNode] = []
    private var prefixes: [String: [String]] = ["xml": ["http://www.w3.org/XML/1998/namespace"]]
    private var lyricNodes = 0

    func parser(_ parser: XMLParser, didStartMappingPrefix prefix: String, toURI namespaceURI: String) { prefixes[prefix, default: []].append(namespaceURI) }
    func parser(_ parser: XMLParser, didEndMappingPrefix prefix: String) { _ = prefixes[prefix]?.popLast() }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
        guard stack.count < 64 else { invalid = true; parser.abortParsing(); return }
        if ["p", "span"].contains(elementName) { lyricNodes += 1 }
        guard lyricNodes <= 20_000 else { invalid = true; parser.abortParsing(); return }
        func attribute(_ name: String, namespace: String) -> String? {
            attributes.first { key, _ in
                let parts = key.split(separator: ":", maxSplits: 1)
                return parts.count == 2 && parts[1] == name && prefixes[String(parts[0])]?.last == namespace
            }?.value
        }
        let node = TTMLNode(name: elementName, namespace: namespaceURI, attributes: attributes,
                            role: attribute("role", namespace: metadataNamespace),
                            language: attribute("lang", namespace: "http://www.w3.org/XML/1998/namespace"))
        if let parent = stack.last { parent.content.append(.node(node)) }
        else if root == nil { root = node }
        else { invalid = true; parser.abortParsing(); return }
        stack.append(node)
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) { _ = stack.popLast() }
    func parser(_ parser: XMLParser, foundCharacters string: String) { stack.last?.content.append(.text(string)) }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard let text = String(data: CDATABlock, encoding: .utf8) else { invalid = true; parser.abortParsing(); return }
        stack.last?.content.append(.text(text))
    }
    func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? { invalid = true; parser.abortParsing(); return nil }
}

func parseCommunityTTML(_ text: String) -> [CommunityLyricLine] {
    guard text.utf8.count <= 1_048_576, text.range(of: "<!DOCTYPE", options: .caseInsensitive) == nil,
          text.range(of: "<!ENTITY", options: .caseInsensitive) == nil else { return [] }
    let delegate = CommunityTTMLParser(), parser = XMLParser(data: Data(text.utf8))
    parser.shouldProcessNamespaces = true
    parser.shouldReportNamespacePrefixes = true
    parser.shouldResolveExternalEntities = false
    parser.delegate = delegate
    guard parser.parse(), !delegate.invalid, let root = delegate.root, root.name == "tt", root.namespace == ttmlNamespace else { return [] }
    var lines: [CommunityLyricLine] = []
    func interval(_ node: TTMLNode, required: Bool) -> (Double, Double)? {
        guard let begin = node.attributes["begin"], let end = node.attributes["end"],
              let start = communityTime(begin), let stop = communityTime(end),
              stop > start || (!required && stop == start && node.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) else { return nil }
        return (start, stop)
    }
    func validTimes(_ node: TTMLNode) -> Bool {
        if node.name == "head" { return true }
        if node.attributes["begin"] != nil || node.attributes["end"] != nil {
            guard ["body", "div", "p", "span"].contains(node.name), interval(node, required: node.name != "span") != nil else { return false }
        }
        return node.children.allSatisfy(validTimes)
    }
    func line(_ node: TTMLNode) -> CommunityLyricLine? {
        guard let (start, end) = interval(node, required: true) else { return nil }
        var text = "", words: [CommunityLyricWord] = [], translation: String?
        for part in node.content {
            switch part {
            case .text(let value): text += value
            case .node(let span):
                guard span.namespace == ttmlNamespace, span.name == "span" else { return nil }
                if span.role == "x-bg" || span.role == "x-roman" { continue }
                guard span.children.isEmpty else { return nil }
                let timed = span.attributes["begin"] != nil || span.attributes["end"] != nil
                let timing = timed ? interval(span, required: false) : nil
                if timed && timing == nil { return nil }
                if span.role == "x-translation" {
                    if translation == nil, span.language == nil || span.language!.lowercased().hasPrefix("zh"),
                       !span.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { translation = span.text }
                    continue
                }
                guard span.role == nil else { return nil }
                let spanText = span.text
                let range = NSRange(location: text.utf16.count, length: spanText.utf16.count)
                text += spanText
                if let (begin, stop) = timing {
                    guard begin >= start, stop <= end, begin >= (words.last?.start ?? start) else { return nil }
                    if !spanText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { words.append(CommunityLyricWord(start: begin, end: stop, text: spanText, utf16Range: range)) }
                }
            }
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return CommunityLyricLine(start: start, end: end, text: text, translation: translation, words: words)
    }
    func visit(_ node: TTMLNode, parent: String?, bounds: (Double, Double)? = nil) -> Bool {
        guard node.namespace == ttmlNamespace else { return false }
        if node.name == "head" { return parent == "tt" }
        if node.name == "p" {
            guard parent == "div", let parsed = line(node),
                  bounds.map({ parsed.start >= $0.0 && parsed.end <= $0.1 }) ?? true else { return false }
            lines.append(parsed); return true
        }
        guard (node.name == "tt" && parent == nil) || (node.name == "body" && parent == "tt") || (node.name == "div" && ["body", "div"].contains(parent)) else { return false }
        var childBounds = bounds
        if node.attributes["begin"] != nil || node.attributes["end"] != nil {
            guard let range = interval(node, required: true), bounds.map({ range.0 >= $0.0 && range.1 <= $0.1 }) ?? true else { return false }
            childBounds = range
        }
        return node.children.allSatisfy { visit($0, parent: node.name, bounds: childBounds) }
    }
    guard validTimes(root), visit(root, parent: nil) else { return [] }
    // Overlapping containers can interleave lines; retain document order for tied starts.
    return lines.enumerated().sorted { $0.element.start == $1.element.start ? $0.offset < $1.offset : $0.element.start < $1.element.start }.map(\.element)

}

func communityLRCLines(_ text: String, duration: Double) -> [CommunityLyricLine] {
    let lines = parseLRC(text)
    guard lines.count <= 20_000, lines.contains(where: { !$0.text.isEmpty }) else { return [] }
    return lines.enumerated().map { index, line in
        CommunityLyricLine(start: line.time, end: index + 1 < lines.count ? lines[index + 1].time : max(line.time, duration), text: line.text, translation: nil, words: [])
    }
}
