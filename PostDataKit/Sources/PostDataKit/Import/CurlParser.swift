import Foundation

public enum CurlParseError: LocalizedError, Equatable {
    case notCurlCommand
    case missingURL
    case missingValue(String)

    public var errorDescription: String? {
        switch self {
        case .notCurlCommand: "不是有效的 cURL 命令（需要以 curl 开头）"
        case .missingURL: "cURL 命令中没有找到 URL"
        case .missingValue(let flag): "参数 \(flag) 缺少值"
        }
    }
}

/// Converts a cURL command (e.g. from a browser's "Copy as cURL") into an `HTTPRequest`.
public enum CurlParser {
    /// True when the text looks like a cURL command worth trying to import.
    public static func looksLikeCurl(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPrompt = trimmed.hasPrefix("$ ") ? String(trimmed.dropFirst(2)) : trimmed
        return withoutPrompt.lowercased().hasPrefix("curl ")
    }

    private enum DataKind { case ascii, raw, binary, urlencode }
    private struct DataArgument { var kind: DataKind; var value: String }

    // Short options that take a value; every other short option is treated as a boolean flag.
    private static let shortWithValue: Set<Character> = [
        "X", "H", "d", "F", "u", "A", "e", "b", "o", "T", "m", "w", "x", "c", "E", "K", "r", "y", "Y", "z", "U", "C", "Q", "t",
    ]

    private static let longWithValue: Set<String> = [
        "request", "header", "data", "data-raw", "data-binary", "data-ascii", "data-urlencode", "json",
        "form", "form-string", "user", "user-agent", "referer", "cookie", "url", "output", "upload-file",
        "max-time", "connect-timeout", "proxy", "proxy-user", "cookie-jar", "write-out", "cert", "key",
        "cacert", "capath", "resolve", "connect-to", "oauth2-bearer", "range", "retry", "retry-delay",
        "retry-max-time", "limit-rate", "max-redirs", "interface", "dns-servers", "config", "request-target",
        "aws-sigv4", "unix-socket", "abstract-unix-socket", "cert-type", "key-type", "pass", "ciphers",
        "tls-max", "expect100-timeout", "happy-eyeballs-timeout-ms", "keepalive-time", "local-port",
        "preproxy", "proxy-header", "noproxy", "socks5", "socks5-hostname", "trace", "trace-ascii", "stderr",
        "time-cond", "variable", "url-query",
    ]

    public static func parse(_ command: String) throws -> HTTPRequest {
        var text = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("$ ") { text.removeFirst(2) }
        var tokens = try ShellTokenizer.tokenize(text)
        guard let first = tokens.first, first.lowercased() == "curl" || first.hasSuffix("/curl") else {
            throw CurlParseError.notCurlCommand
        }
        tokens.removeFirst()

        var method: String?
        var url: String?
        var headers: [KeyValue] = []
        var data: [DataArgument] = []
        var form: [(value: String, isString: Bool)] = []
        var auth: Auth?
        var forceGet = false
        var head = false
        var settings = RequestSettings()
        var urlQueries: [String] = []

        var index = 0
        func nextValue(for flag: String) throws -> String {
            index += 1
            guard index < tokens.count else { throw CurlParseError.missingValue(flag) }
            return tokens[index]
        }

        func apply(long name: String, value: String?) throws {
            func required() throws -> String {
                if let value { return value }
                return try nextValue(for: "--" + name)
            }
            switch name {
            case "request": method = try required()
            case "header": if let header = parseHeader(try required()) { headers.append(header) }
            case "data", "data-ascii": data.append(DataArgument(kind: .ascii, value: try required()))
            case "data-raw": data.append(DataArgument(kind: .raw, value: try required()))
            case "data-binary": data.append(DataArgument(kind: .binary, value: try required()))
            case "data-urlencode": data.append(DataArgument(kind: .urlencode, value: try required()))
            case "json":
                data.append(DataArgument(kind: .raw, value: try required()))
                if !headers.contains(where: { $0.key.lowercased() == "content-type" }) {
                    headers.append(KeyValue(key: "Content-Type", value: "application/json"))
                }
                if !headers.contains(where: { $0.key.lowercased() == "accept" }) {
                    headers.append(KeyValue(key: "Accept", value: "application/json"))
                }
            case "form": form.append((try required(), false))
            case "form-string": form.append((try required(), true))
            case "user": auth = basicAuth(try required())
            case "user-agent": headers.append(KeyValue(key: "User-Agent", value: try required()))
            case "referer": headers.append(KeyValue(key: "Referer", value: try required()))
            case "cookie":
                let cookie = try required()
                if cookie.contains("=") { headers.append(KeyValue(key: "Cookie", value: cookie)) }
            case "url": url = try required()
            case "url-query": urlQueries.append(try required())
            case "oauth2-bearer": auth = .bearer(try required())
            case "max-time":
                if let seconds = TimeInterval(try required()) { settings.timeout = seconds }
            case "get": forceGet = true
            case "head": head = true
            case "insecure": settings.validateSSL = false
            case "location", "location-trusted": settings.followRedirects = true
            default:
                if longWithValue.contains(name), value == nil { _ = try nextValue(for: "--" + name) }
            }
        }

        func apply(short flag: Character, value: String?) throws {
            let long: String? = switch flag {
            case "X": "request"
            case "H": "header"
            case "d": "data"
            case "F": "form"
            case "u": "user"
            case "A": "user-agent"
            case "e": "referer"
            case "b": "cookie"
            case "m": "max-time"
            case "G": "get"
            case "I": "head"
            case "k": "insecure"
            case "L": "location"
            default: nil
            }
            if let long {
                try apply(long: long, value: value)
            } else if shortWithValue.contains(flag), value == nil {
                _ = try nextValue(for: "-" + String(flag))
            }
        }

        while index < tokens.count {
            let token = tokens[index]
            if token.hasPrefix("--"), token.count > 2 {
                let body = token.dropFirst(2)
                if let equals = body.firstIndex(of: "="), longWithValue.contains(String(body[..<equals])) {
                    try apply(long: String(body[..<equals]), value: String(body[body.index(after: equals)...]))
                } else {
                    try apply(long: String(body), value: nil)
                }
            } else if token.hasPrefix("-"), token.count > 1 {
                let flags = Array(token.dropFirst())
                var position = 0
                while position < flags.count {
                    let flag = flags[position]
                    if shortWithValue.contains(flag) {
                        let rest = String(flags[(position + 1)...])
                        try apply(short: flag, value: rest.isEmpty ? nil : rest)
                        break
                    }
                    try apply(short: flag, value: nil)
                    position += 1
                }
            } else if url == nil {
                url = token
            }
            index += 1
        }

        guard var urlString = url, !urlString.isEmpty else { throw CurlParseError.missingURL }

        for query in urlQueries {
            urlString += (urlString.contains("?") ? "&" : "?") + query
        }

        // Build the data payload the way curl does: arguments joined with '&'.
        let payload = data.map { argument -> String in
            switch argument.kind {
            case .urlencode: return encodeDataURLEncode(argument.value)
            case .ascii:
                // curl strips newlines from --data (but not --data-binary/--data-raw).
                return argument.value.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
            case .raw, .binary: return argument.value
            }
        }.joined(separator: "&")

        if forceGet, !payload.isEmpty {
            urlString += (urlString.contains("?") ? "&" : "?") + payload
        }

        var request = HTTPRequest(name: HTTPRequest.suggestedName(for: urlString), url: urlString)
        if let auth { request.auth = auth }
        request.settings = settings

        let contentType = headers.last { $0.key.lowercased() == "content-type" }?.value.lowercased()

        if !form.isEmpty {
            request.body.mode = .formData
            request.body.formData = form.map { parseFormField($0.value, isString: $0.isString) }
        } else if !data.isEmpty, !forceGet {
            let singleFile = data.count == 1 && (data[0].kind == .ascii || data[0].kind == .binary) && data[0].value.hasPrefix("@")
            if singleFile {
                request.body.mode = .binary
                request.body.binaryFilePath = String(data[0].value.dropFirst())
            } else if let contentType, contentType.contains("application/x-www-form-urlencoded") {
                request.body.mode = .urlEncoded
                request.body.urlEncoded = parseURLEncoded(payload)
            } else if let contentType {
                request.body.mode = .raw
                request.body.raw = payload
                request.body.rawLanguage = RequestBody.RawLanguage(contentType: contentType) ?? .text
            } else if ResponseContent.looksLikeJSON(payload) {
                request.body.mode = .raw
                request.body.raw = payload
                request.body.rawLanguage = .json
            } else if looksURLEncoded(payload) {
                request.body.mode = .urlEncoded
                request.body.urlEncoded = parseURLEncoded(payload)
            } else {
                request.body.mode = .raw
                request.body.raw = payload
                request.body.rawLanguage = .text
            }
        }

        // Pretty-print JSON bodies so they are pleasant to edit.
        if request.body.mode == .raw, request.body.rawLanguage == .json, let pretty = JSONFormatter.prettyPrint(request.body.raw) {
            request.body.raw = pretty
        }

        request.headers = headers
        let hasBody = !form.isEmpty || (!data.isEmpty && !forceGet)
        if let method {
            request.method = HTTPMethod(method)
        } else if head {
            request.method = .head
        } else if hasBody {
            request.method = .post
        } else {
            request.method = .get
        }
        return request
    }

    // MARK: Helpers

    static func parseHeader(_ line: String) -> KeyValue? {
        if let colon = line.firstIndex(of: ":") {
            let name = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? nil : KeyValue(key: name, value: value)
        }
        // `-H 'X-Empty;'` sends an empty header.
        if line.hasSuffix(";") {
            return KeyValue(key: String(line.dropLast()).trimmingCharacters(in: .whitespaces), value: "")
        }
        return nil
    }

    static func basicAuth(_ credentials: String) -> Auth {
        if let colon = credentials.firstIndex(of: ":") {
            return .basic(username: String(credentials[..<colon]), password: String(credentials[credentials.index(after: colon)...]))
        }
        return .basic(username: credentials, password: "")
    }

    static func parseFormField(_ spec: String, isString: Bool) -> FormDataField {
        guard let equals = spec.firstIndex(of: "=") else {
            return FormDataField(key: spec)
        }
        let name = String(spec[..<equals])
        var value = String(spec[spec.index(after: equals)...])
        if !isString, value.hasPrefix("@") {
            value.removeFirst()
            var contentType: String?
            // name=@file;type=image/png;filename=x.png
            let parts = value.split(separator: ";").map(String.init)
            if let path = parts.first { value = path }
            for part in parts.dropFirst() where part.hasPrefix("type=") {
                contentType = String(part.dropFirst(5))
            }
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            return FormDataField(key: name, kind: .file, filePath: value, contentType: contentType)
        }
        if !isString, value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            value = String(value.dropFirst().dropLast())
        }
        return FormDataField(key: name, kind: .text, value: value)
    }

    static func looksURLEncoded(_ payload: String) -> Bool {
        guard !payload.isEmpty, !payload.contains(" "), !payload.contains("\n") else { return false }
        return payload.split(separator: "&").allSatisfy { pair in
            guard let equals = pair.firstIndex(of: "=") else { return false }
            return !pair[..<equals].isEmpty
        }
    }

    /// Splits and decodes `a=1&b=x+y` into rows (values are re-encoded when sending).
    static func parseURLEncoded(_ payload: String) -> [KeyValue] {
        func decode(_ s: Substring) -> String {
            let plusDecoded = s.replacingOccurrences(of: "+", with: " ")
            return plusDecoded.removingPercentEncoding ?? plusDecoded
        }
        return payload.split(separator: "&", omittingEmptySubsequences: true).map { pair in
            if let equals = pair.firstIndex(of: "=") {
                return KeyValue(key: decode(pair[..<equals]), value: decode(pair[pair.index(after: equals)...]))
            }
            return KeyValue(key: decode(pair), value: "")
        }
    }

    /// Mirrors `--data-urlencode` semantics: `name=content` encodes only the content.
    static func encodeDataURLEncode(_ value: String) -> String {
        if let equals = value.firstIndex(of: "=") {
            let name = String(value[..<equals])
            let content = String(value[value.index(after: equals)...])
            return name.isEmpty ? RequestBuilder.formURLEncode(content) : name + "=" + RequestBuilder.formURLEncode(content)
        }
        return RequestBuilder.formURLEncode(value)
    }
}
