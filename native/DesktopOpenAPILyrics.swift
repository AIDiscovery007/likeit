import Foundation
import Darwin

// Lifecycle and delegate callbacks stay on main; parsing runs separately.
// No credential storage, cookies, cache, or redirects.
final class LyricRequest: NSObject, URLSessionDataDelegate {
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var data = Data()
    private var rejected = false
    private var completion: ((Result<Data, Error>) -> Void)?
    private var responseReceived: ((HTTPURLResponse) -> Void)?

    private let sessionConfiguration: URLSessionConfiguration

    init(sessionConfiguration: URLSessionConfiguration) {
        self.sessionConfiguration = sessionConfiguration.copy() as! URLSessionConfiguration
    }

    func start(_ request: URLRequest, responseReceived: ((HTTPURLResponse) -> Void)? = nil, completion: @escaping (Result<Data, Error>) -> Void) {
        self.completion = completion
        self.responseReceived = responseReceived
        let config = sessionConfiguration.copy() as! URLSessionConfiguration
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        task = session!.dataTask(with: request)
        task!.resume()
    }
    func cancel() { task?.cancel() }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let http = response as? HTTPURLResponse { responseReceived?(http) }
        let valid = (response as? HTTPURLResponse)?.statusCode == 200 && response.expectedContentLength <= 1_048_576
        rejected = !valid
        completionHandler(valid ? .allow : .cancel)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        if data.count + chunk.count > 1_048_576 { rejected = true; dataTask.cancel() } else { data.append(chunk) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let callback = completion
        completion = nil
        responseReceived = nil
        callback?(rejected ? .failure(URLError(.badServerResponse)) : error.map { .failure($0) } ?? .success(data))
        data.removeAll()
        session.invalidateAndCancel()
        self.session = nil
        self.task = nil
    }
}


private enum OpenAPILyricError: Error {
    case configuration, manifest, mapping, response, api, transport, signing

    var message: String {
        switch self {
        case .configuration: return "官方歌词配置不可用 · 请检查配置、私钥及文件权限"
        case .manifest: return "官方歌词不可用 · 命令清单缺失或不受支持"
        case .mapping: return "官方歌词不可用 · 未确认唯一歌曲 ID 映射"
        case .response: return "官方歌词不可用 · 响应格式无效"
        case .api: return "官方歌词不可用 · 接口拒绝请求"
        case .transport: return "官方歌词不可用 · 网络或响应大小限制"
        case .signing: return "官方歌词不可用 · 请求签名失败"
        }
    }
}

private func nonblank(_ value: String) -> Bool { !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
private func positiveDecimal(_ value: String) -> Bool {
    guard let first = value.utf8.first, (49...57).contains(first) else { return false }
    return value.utf8.allSatisfy { (48...57).contains($0) }
}
private func boolean(_ value: Any) -> Bool? {
    guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
    return number.boolValue
}
private func number(_ value: Any) -> NSNumber? {
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { return nil }
    return number
}

enum OpenAPILyricSource: String { case word, standard }

struct OpenAPILyricConfiguration {
    let appID: String
    let accessToken: String
    let privateKeyPEM: String
    let device: [String: String]
    var lyricSource: OpenAPILyricSource = .word

    static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Likeit/netease-openapi.json")
    }

    // Inspect the opened file, not a prior path lookup; never follow a file symlink.
    private static func read(_ url: URL, missingAllowed: Bool = false) throws -> Data? {
        guard url.isFileURL, !url.path.utf8.contains(0) else { throw OpenAPILyricError.configuration }
        let fd = Darwin.open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else {
            if missingAllowed && errno == ENOENT { return nil }
            throw OpenAPILyricError.configuration
        }
        defer { Darwin.close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_mode & 0o077 == 0, info.st_size >= 0, info.st_size <= 65_536 else { throw OpenAPILyricError.configuration }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(fd, &buffer, min(buffer.count, 65_537 - data.count))
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw OpenAPILyricError.configuration }
            if count == 0 { return data }
            data.append(contentsOf: buffer.prefix(count))
            guard data.count <= 65_536 else { throw OpenAPILyricError.configuration }
        }
    }

    static func load(from url: URL) throws -> OpenAPILyricConfiguration? {
        do {
            guard let data = try read(url, missingAllowed: true) else { return nil }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let appID = json["appId"] as? String, nonblank(appID),
                  let accessToken = json["accessToken"] as? String, nonblank(accessToken),
                  json["lyricSource"] == nil || json["lyricSource"] is String,
                  let source = OpenAPILyricSource(rawValue: json["lyricSource"] as? String ?? "word"),
                  let path = json["privateKeyPath"] as? String, path.hasPrefix("/"), !path.utf8.contains(0),
                  let device = json["device"] as? [String: String], !device.isEmpty,
                  device.allSatisfy({ nonblank($0.key) && nonblank($0.value) }),
                  let pemData = try read(URL(fileURLWithPath: path)),
                  let pem = String(data: pemData, encoding: .utf8) else { throw OpenAPILyricError.configuration }
            _ = try openAPISignature(parameters: [:], privateKeyPEM: pem)
            return OpenAPILyricConfiguration(appID: appID, accessToken: accessToken, privateKeyPEM: pem, device: device, lyricSource: source)
        } catch { throw OpenAPILyricError.configuration }
    }
}

enum OpenAPILyricOutcome {
    case lines([LyricLine])
    case noSynchronizedLyrics
    case unavailable(String)
}

private struct OpenAPICommand {
    let path: String
    let method: String
    let authenticated: Bool
    let business: [String: Any]

    static func resolve(_ manifests: [String: Any], resource: String, name: String, provided: [String: Any], identity: String) throws -> OpenAPICommand {
        guard let root = manifests["root"] as? [String: Any], let resources = root["sub_resources"] as? [[String: Any]] else { throw OpenAPILyricError.manifest }
        let matches = resources.filter { $0["name"] as? String == resource }
        guard matches.count == 1, let key = matches[0]["path"] as? String,
              let entry = manifests[key] as? [String: Any], let methods = entry["methods"] as? [[String: Any]] else { throw OpenAPILyricError.manifest }
        let targets = methods.filter { $0["name"] as? String == name }
        guard targets.count == 1 else { throw OpenAPILyricError.manifest }
        let descriptor = targets[0]
        guard let path = descriptor["path"] as? String, path.hasPrefix("/openapi/"), path.count > 9, !path.contains("//"),
              path.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || [45, 47, 95].contains($0) }),
              let method = descriptor["http_method"] as? String, ["GET", "POST"].contains(method) else { throw OpenAPILyricError.manifest }
        var authenticated = true
        if let auth = descriptor["auth_required"] {
            guard let flag = boolean(auth) else { throw OpenAPILyricError.manifest }
            authenticated = flag
        }
        if authenticated, let provider = descriptor["auth_provider"], provider as? String != "netease" { throw OpenAPILyricError.manifest }
        let parameters: [[String: Any]]
        if let list = descriptor["parameters"] as? [[String: Any]] { parameters = list }
        else if let map = descriptor["parameters"] as? [String: [String: Any]] {
            parameters = try map.map { key, value in
                guard value["name"] == nil || value["name"] as? String == key else { throw OpenAPILyricError.manifest }
                return value.merging(["name": key]) { _, new in new }
            }
        } else { throw OpenAPILyricError.manifest }
        let fixed: [String: Any]
        if let value = descriptor["fixed_params"], !(value is NSNull) {
            guard let values = value as? [String: Any], values.values.allSatisfy(Self.scalar), method != "GET" || values.isEmpty else { throw OpenAPILyricError.manifest }
            fixed = values
        } else { fixed = [:] }
        for (name, value) in fixed {
            if let input = provided[name], !Self.equalScalars(value, input) { throw OpenAPILyricError.manifest }
        }
        var names = Set<String>(), business: [String: Any] = [:]
        for parameter in parameters {
            guard let name = parameter["name"] as? String, nonblank(name), names.insert(name).inserted,
                  parameter["in"] == nil || parameter["in"] is String,
                  let location = (parameter["in"] as? String).flatMap({ $0.isEmpty ? nil : $0 }) ?? parameter["location"] as? String, ["query", "body"].contains(location) else { throw OpenAPILyricError.manifest }
            let type = parameter["type"] as? String
            guard parameter["type"] == nil || (type != nil && ["string", "integer", "number", "boolean"].contains(type!)) else { throw OpenAPILyricError.manifest }
            var required = false
            if let value = parameter["required"] {
                guard let flag = boolean(value) else { throw OpenAPILyricError.manifest }
                required = flag
            }
            let fallback = parameter["default"].flatMap { $0 is NSNull ? nil : $0 }
            guard let value = fixed[name] ?? provided[name] ?? fallback else {
                if required { throw OpenAPILyricError.manifest }
                continue
            }
            guard Self.scalar(value), !(required && (value as? String).map({ !nonblank($0) }) == true) else { throw OpenAPILyricError.manifest }
            switch type {
            case "string": guard value is String else { throw OpenAPILyricError.manifest }
            case "boolean": guard boolean(value) != nil else { throw OpenAPILyricError.manifest }
            case "number": guard number(value) != nil else { throw OpenAPILyricError.manifest }
            case "integer": guard openAPIInteger(value) != nil else { throw OpenAPILyricError.manifest }
            default: break
            }
            if method == "GET" && location == "body" {
                if required { throw OpenAPILyricError.manifest }
                continue
            }
            business[name] = value
        }
        // Required identity must come from a declared, transmitted input.
        guard provided[identity] != nil, business[identity] != nil else { throw OpenAPILyricError.manifest }
        business.merge(fixed) { _, value in value }
        return OpenAPICommand(path: path, method: method, authenticated: authenticated, business: business)
    }

    private static func scalar(_ value: Any) -> Bool { value is String || boolean(value) != nil || number(value) != nil }

    private static func equalScalars(_ lhs: Any, _ rhs: Any) -> Bool {
        if let left = lhs as? String, let right = rhs as? String { return left == right }
        if let left = boolean(lhs), let right = boolean(rhs) { return left == right }
        guard let left = number(lhs), let right = number(rhs) else { return false }
        return left.decimalValue == right.decimalValue
    }
}

private let openAPIParsing = DispatchQueue(label: "com.likeit.desktop.openapi", qos: .userInitiated)

final class OpenAPILyrics {
    private let configuration: OpenAPILyricConfiguration
    private let sessionConfiguration: URLSessionConfiguration
    private var generation = UUID()
    private var request: LyricRequest?
    private var deadline: DispatchWorkItem?
    private var completion: ((OpenAPILyricOutcome) -> Void)?

    init(configuration: OpenAPILyricConfiguration, sessionConfiguration: URLSessionConfiguration = .ephemeral) {
        self.configuration = configuration
        self.sessionConfiguration = sessionConfiguration.copy() as! URLSessionConfiguration
    }

    func cancel() {
        generation = UUID()
        completion = nil
        request?.cancel(); request = nil
        deadline?.cancel(); deadline = nil
    }

    func load(originalID: String, keyword: String, completion: @escaping (OpenAPILyricOutcome) -> Void) {
        cancel()
        self.completion = completion
        guard positiveDecimal(originalID), nonblank(keyword) else { finish(.unavailable(OpenAPILyricError.mapping.message)); return }
        let token = generation
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.generation == token else { return }
            self.finish(.unavailable("官方歌词不可用 · 请求超时"))
        }
        deadline = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeout)
        let manifest = OpenAPICommand(path: "/openapi/v1/ncm/cli/manifest", method: "POST", authenticated: true, business: ["cliVersion": "0.1.7", "cachedVersion": "{}"])
        send(manifest, token: token, decode: { data in
            let json = try Self.json(data, codeRequired: false)
            guard let manifests = json["manifests"] as? [String: Any] else { throw OpenAPILyricError.manifest }
            return (manifests, try OpenAPICommand.resolve(manifests, resource: "search", name: "song", provided: ["keyword": keyword, "limit": 20], identity: "keyword"))
        }) { [weak self] manifests, command in
            self?.send(command, token: token, decode: { try Self.mappedID($0, originalID: originalID) }) { [weak self] id in
                guard let self else { return }
                if self.configuration.lyricSource == .standard {
                    self.loadOrdinary(manifests: manifests, id: id, token: token)
                    return
                }
                let word = OpenAPICommand(path: "/openapi/music/basic/song/lyric/word/by/word/get", method: "POST", authenticated: true, business: ["songId": id])
                self.send(word, token: token, decode: decodeOpenAPIWordLyrics) { [weak self] result in
                    guard let self else { return }
                    switch result {
                    case .lines(let lines): self.finish(.lines(lines))
                    case .apiError: self.finish(.unavailable(OpenAPILyricError.api.message))
                    case .malformed: self.finish(.unavailable(OpenAPILyricError.response.message))
                    case .noWordLyrics, .noSynchronizedLyrics:
                        self.loadOrdinary(manifests: manifests, id: id, token: token)
                    }
                }
            }
        }
    }

    private func loadOrdinary(manifests: [String: Any], id: String, token: UUID) {
        work(token: token, operation: {
            try OpenAPICommand.resolve(manifests, resource: "song", name: "lyric", provided: ["songId": id], identity: "songId")
        }) { [weak self] ordinary in
            self?.send(ordinary, token: token, decode: Self.ordinaryLyrics) { [weak self] in self?.finish($0) }
        }
    }

    private func finish(_ outcome: OpenAPILyricOutcome) {
        let callback = completion
        cancel()
        callback?(outcome)
    }

    // Check generation before both starting dependent work and publishing its result.
    private func work<T>(token: UUID, operation: @escaping () throws -> T, completion: @escaping (T) -> Void) {
        guard generation == token else { return }
        openAPIParsing.async { [weak self] in
            let result = Result { try operation() }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token else { return }
                switch result {
                case .success(let value): completion(value)
                case .failure(let error): self.finish(.unavailable((error as? OpenAPILyricError ?? .response).message))
                }
            }
        }
    }

    private func send<T>(_ command: OpenAPICommand, token: UUID, decode: @escaping (Data) throws -> T, completion: @escaping (T) -> Void) {
        let configuration = configuration
        work(token: token, operation: {
            var fields = ["appId": configuration.appID, "signType": "RSA_SHA256", "timestamp": String(Int64(Date().timeIntervalSince1970 * 1000)),
                          "device": String(decoding: try JSONSerialization.data(withJSONObject: configuration.device), as: UTF8.self),
                          "bizContent": String(decoding: try JSONSerialization.data(withJSONObject: command.business), as: UTF8.self)]
            if command.authenticated { fields["accessToken"] = configuration.accessToken }
            do { fields["sign"] = try openAPISignature(parameters: fields, privateKeyPEM: configuration.privateKeyPEM) }
            catch { throw OpenAPILyricError.signing }
            var url = URLComponents()
            url.scheme = "https"; url.host = "openapi.music.163.com"; url.path = command.path
            if command.method == "GET" {
                url.queryItems = fields.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
                // Form/query decoders interpret a bare '+' as a space.
                url.percentEncodedQuery = url.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
            }
            guard let address = url.url else { throw OpenAPILyricError.manifest }
            var request = URLRequest(url: address, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
            request.httpMethod = command.method
            request.setValue("Likeit/1.0", forHTTPHeaderField: "User-Agent")
            if command.method == "POST" {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: fields)
            }
            return request
        }) { [weak self] payload in
            guard let self else { return }
            let request = LyricRequest(sessionConfiguration: self.sessionConfiguration)
            self.request = request
            request.start(payload) { [weak self] result in
                self?.work(token: token, operation: {
                    guard case .success(let data) = result else { throw OpenAPILyricError.transport }
                    return try decode(data)
                }, completion: completion)
            }
        }
    }

    private static func json(_ data: Data, codeRequired: Bool = true) throws -> [String: Any] {
        guard let json = try decodeOpenAPIJSON(data) as? [String: Any] else { throw OpenAPILyricError.response }
        if let value = json["code"] {
            guard let code = openAPIInteger(value) else { throw OpenAPILyricError.response }
            guard code == 200 else { throw OpenAPILyricError.api }
        } else if codeRequired { throw OpenAPILyricError.response }
        return json
    }

    private static func mappedID(_ data: Data, originalID: String) throws -> String {
        let json = try json(data)
        let payload = json["data"]
        let container = payload as? [String: Any]
        let records = container?["songs"] == nil && container?["list"] == nil && container?["records"] != nil
        let rows: [[String: Any]]
        if let list = (container?["songs"] ?? container?["list"] ?? container?["records"] ?? payload) as? [[String: Any]] { rows = list }
        else if let map = container, map.keys.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }), let values = Array(map.values) as? [[String: Any]] { rows = values }
        else { throw OpenAPILyricError.mapping }
        guard rows.count <= 100 else { throw OpenAPILyricError.mapping }
        var matches = Set<String>()
        for row in rows {
            let original: String?
            if let text = row["originalId"] as? String { original = positiveDecimal(text) ? text : nil }
            else if let value = row["originalId"], let id = openAPIInteger(value), id > 0, id <= 9_007_199_254_740_991 { original = String(id) }
            else { original = nil }
            guard original == originalID else { continue }
            var ids = Set<String>()
            for name in records ? ["songId", "encryptedId", "id"] : ["songId", "encryptedId"] {
                guard let value = row[name] else { continue }
                guard let text = value as? String, text.utf8.count == 32,
                      text.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else { throw OpenAPILyricError.mapping }
                ids.insert(text.lowercased())
            }
            guard ids.count == 1 else { throw OpenAPILyricError.mapping }
            matches.formUnion(ids)
        }
        guard matches.count == 1, let id = matches.first else { throw OpenAPILyricError.mapping }
        return id
    }

    private static func ordinaryLyrics(_ data: Data) throws -> OpenAPILyricOutcome {
        let json = try json(data)
        guard let value = json["data"] else { throw OpenAPILyricError.response }
        if value is NSNull { return .noSynchronizedLyrics }
        guard let lyrics = value as? [String: Any] else { throw OpenAPILyricError.response }
        let original = lyrics["lyric"]
        guard original == nil || original is NSNull || original is String else { throw OpenAPILyricError.response }
        var text = original as? String ?? ""
        if text.isEmpty, let lrc = lyrics["lrc"], !(lrc is NSNull) {
            guard let nested = lrc as? [String: Any] else { throw OpenAPILyricError.response }
            let fallback = nested["lyric"]
            guard fallback == nil || fallback is NSNull || fallback is String else { throw OpenAPILyricError.response }
            text = fallback as? String ?? ""
        }
        let lines = parseLRC(text)
        return lines.contains(where: { !$0.text.isEmpty }) ? .lines(lines) : .noSynchronizedLyrics
    }
}
