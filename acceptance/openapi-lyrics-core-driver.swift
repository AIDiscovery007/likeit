import Foundation

@main
struct OpenAPICoreAcceptance {
    static func main() throws {
        let fixture = URL(fileURLWithPath: CommandLine.arguments[1])
        let key = try String(contentsOf: fixture.appendingPathComponent("private.pem"), encoding: .utf8)
        let answers = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture.appendingPathComponent("signatures.json"))) as! [[String: Any]]
        var checks: [[String: Any]] = []
        func check(_ name: String, _ passed: Bool) { checks.append(["name": name, "passed": passed]) }
        for (index, answer) in answers.enumerated() {
            let signature = try openAPISignature(parameters: answer["parameters"] as! [String: String], privateKeyPEM: key)
            check("signature known answer \(index + 1)", signature == answer["signature"] as? String)
        }
        do { _ = try openAPISignature(parameters: ["appId": "fixture"], privateKeyPEM: ""); check("empty key rejected", false) }
        catch { check("empty key rejected", true) }
        do { _ = try openAPISignature(parameters: ["appId": "fixture"], privateKeyPEM: "fixture-invalid-private-key"); check("bad key rejected safely", false) }
        catch { check("bad key rejected safely", !String(describing: error).contains("fixture-invalid-private-key")) }
        func decode(_ object: Any) throws -> OpenAPIWordLyricResult { decodeOpenAPIWordLyrics(try JSONSerialization.data(withJSONObject: object)) }
        let lrc = "[00:01.000]向前\n[00:02.200]\n[00:03.500]继续"
        if case .lines(let lines) = try decode(["code": 200, "data": ["lrc": lrc, "lyrics": [["start": "bad"]], "tlyric": "[00:01]translation"]]) {
            check("original lrc drives existing timeline", lines.count == 3 && lines[0].text == "向前" && lines[1].text.isEmpty && lines[2].time == 3.5 && activeLyricIndex(in: lines, at: 2.5) == 1)
        } else { check("original lrc drives existing timeline", false) }
        if case .lines = try decode(["code": 200, "data": ["lrc": lrc]]) { check("word array not required for lrc", true) } else { check("word array not required for lrc", false) }
        if case .noWordLyrics = try decode(["code": 200, "data": NSNull()]) { check("null distinguishes no word lyrics", true) } else { check("null distinguishes no word lyrics", false) }
        if case .noSynchronizedLyrics = try decode(["code": 200, "data": ["tlyric": lrc, "ytlrcs": lrc, "lyrics": [["start": 0, "words": [["words": "not lrc"]]]]]]) { check("translation and words not substituted", true) } else { check("translation and words not substituted", false) }
        if case .noSynchronizedLyrics = try decode(["code": 200, "data": ["lrc": "[ar:fixture]\nuntimed"]]) { check("untimed text has no synchronized lyrics", true) } else { check("untimed text has no synchronized lyrics", false) }
        if case .noSynchronizedLyrics = try decode(["code": 200, "data": ["lrc": "[00:01]\n[00:02]"]]) { check("blank timed text is not lyrics success", true) } else { check("blank timed text is not lyrics success", false) }
        if case .apiError(403) = try decode(["code": 403, "message": "fixture-secret", "data": ["lrc": lrc]]) { check("api error never returns supplied lyrics", true) } else { check("api error never returns supplied lyrics", false) }
        if case .malformed = try decode(["code": 200.5, "data": NSNull()]) { check("fractional business code rejected", true) } else { check("fractional business code rejected", false) }
        if case .malformed = try decode(["code": 200]) { check("missing data not confused with null", true) } else { check("missing data not confused with null", false) }
        if case .malformed = try decode(["code": 200, "data": []]) { check("array data rejected", true) } else { check("array data rejected", false) }
        if case .malformed = try decode(["code": 200, "data": ["lrc": 123]]) { check("nontext lrc rejected", true) } else { check("nontext lrc rejected", false) }
        if case .malformed = decodeOpenAPIWordLyrics(Data("not JSON".utf8)) { check("broken json rejected", true) } else { check("broken json rejected", false) }
        if case .malformed = decodeOpenAPIWordLyrics(Data(repeating: 32, count: 1_048_577)) { check("oversize body rejected", true) } else { check("oversize body rejected", false) }
        let data = try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
