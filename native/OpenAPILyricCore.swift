import Foundation
import Security

private enum OpenAPISigningError: Error { case invalidPrivateKey, signingFailed }

// Only the PKCS#8 envelope is decoded here; Security validates the RSA key itself.
private struct OpenAPIKeyDER {
    private var bytes: ArraySlice<UInt8>

    init(_ data: Data) { bytes = Array(data)[...] }
    var isEmpty: Bool { bytes.isEmpty }

    mutating func read(_ tag: UInt8) throws -> Data {
        guard bytes.popFirst() == tag, let first = bytes.popFirst() else { throw OpenAPISigningError.invalidPrivateKey }
        var length = Int(first)
        if first & 0x80 != 0 {
            let count = Int(first & 0x7f)
            guard count > 0, count <= MemoryLayout<Int>.size, bytes.count >= count, bytes.first != 0 else {
                throw OpenAPISigningError.invalidPrivateKey
            }
            length = 0
            for _ in 0..<count {
                let byte = Int(bytes.removeFirst())
                guard length <= (Int.max - byte) / 256 else { throw OpenAPISigningError.invalidPrivateKey }
                length = length * 256 + byte
            }
            guard length >= 128 else { throw OpenAPISigningError.invalidPrivateKey }
        }
        guard length <= bytes.count else { throw OpenAPISigningError.invalidPrivateKey }
        let value = Data(bytes.prefix(length))
        bytes = bytes.dropFirst(length)
        return value
    }
}

private func openAPIPrivateKey(_ pem: String) throws -> SecKey {
    let header = "-----BEGIN PRIVATE KEY-----", footer = "-----END PRIVATE KEY-----"
    let text = pem.trimmingCharacters(in: .whitespacesAndNewlines)
    guard text.hasPrefix(header), text.hasSuffix(footer) else { throw OpenAPISigningError.invalidPrivateKey }
    let body = text.dropFirst(header.count).dropLast(footer.count).filter { !$0.isWhitespace }
    guard !body.isEmpty, let data = Data(base64Encoded: body) else { throw OpenAPISigningError.invalidPrivateKey }
    var envelope = OpenAPIKeyDER(data)
    var info = OpenAPIKeyDER(try envelope.read(0x30))
    guard envelope.isEmpty, try info.read(0x02) == Data([0]) else { throw OpenAPISigningError.invalidPrivateKey }
    var algorithm = OpenAPIKeyDER(try info.read(0x30))
    let rsaEncryption = Data([0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01])
    guard try algorithm.read(0x06) == rsaEncryption else { throw OpenAPISigningError.invalidPrivateKey }
    if !algorithm.isEmpty {
        guard try algorithm.read(0x05).isEmpty, algorithm.isEmpty else { throw OpenAPISigningError.invalidPrivateKey }
    }
    let keyData = try info.read(0x04)
    guard info.isEmpty, let key = SecKeyCreateWithData(keyData as CFData, [
        kSecAttrKeyType: kSecAttrKeyTypeRSA,
        kSecAttrKeyClass: kSecAttrKeyClassPrivate,
    ] as CFDictionary, nil) else { throw OpenAPISigningError.invalidPrivateKey }
    return key
}

func openAPISignature(parameters: [String: String], privateKeyPEM: String) throws -> String {
    let key = try openAPIPrivateKey(privateKeyPEM)
    let locale = Locale(identifier: "en_US")
    let message = parameters.filter { $0.key != "sign" && !$0.value.isEmpty }
        .sorted { $0.key.compare($1.key, locale: locale) == .orderedAscending }
        .map { "\($0.key)=\($0.value)" }.joined(separator: "&")
    guard let signature = SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA256, Data(message.utf8) as CFData, nil) else {
        throw OpenAPISigningError.signingFailed
    }
    return (signature as Data).base64EncodedString()
}

enum OpenAPIWordLyricResult {
    case lines([LyricLine])
    case noWordLyrics
    case noSynchronizedLyrics
    case apiError(Int)
    case malformed
}

// Keep comparisons in Decimal: NSNumber.compare can round decimal JSON values.
func openAPIInteger(_ value: Any?) -> Int? {
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
          number.doubleValue.isFinite else { return nil }
    let decimal = number.decimalValue
    guard decimal >= Decimal(Int.min), decimal <= Decimal(Int.max),
          decimal == Decimal(number.intValue) else { return nil }
    return number.intValue
}

func decodeOpenAPIWordLyrics(_ data: Data) -> OpenAPIWordLyricResult {
    guard data.count <= 1_048_576,
          let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let code = openAPIInteger(response["code"]) else { return .malformed }
    guard code == 200 else { return .apiError(code) }
    guard let value = response["data"] else { return .malformed }
    if value is NSNull { return .noWordLyrics }
    guard let lyrics = value as? [String: Any] else { return .malformed }
    guard let lrc = lyrics["lrc"], !(lrc is NSNull) else { return .noSynchronizedLyrics }
    guard let text = lrc as? String else { return .malformed }
    let lines = parseLRC(text)
    return lines.contains(where: { !$0.text.isEmpty }) ? .lines(lines) : .noSynchronizedLyrics
}
