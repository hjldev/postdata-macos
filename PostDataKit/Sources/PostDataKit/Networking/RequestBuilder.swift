import Foundation
import UniformTypeIdentifiers

public enum RequestBuildError: LocalizedError, Equatable {
    case emptyURL
    case invalidURL(String)
    case unsupportedScheme(String)
    case fileNotReadable(String)

    public var errorDescription: String? {
        switch self {
        case .emptyURL: "请输入请求 URL"
        case .invalidURL(let url): "无效的 URL：\(url)"
        case .unsupportedScheme(let scheme): "不支持的协议：\(scheme)（仅支持 http / https）"
        case .fileNotReadable(let path): "无法读取文件：\(path)"
        }
    }
}

/// A request with variables substituted and auth applied — everything needed to send it
/// or to generate code for it. Files are referenced by path and only read when sending.
public struct ResolvedRequest: Hashable, Sendable {
    public struct MultipartPart: Hashable, Sendable {
        public enum Content: Hashable, Sendable {
            case text(String)
            case file(path: String)
        }

        public var name: String
        public var content: Content
        public var contentType: String?

        public init(name: String, content: Content, contentType: String? = nil) {
            self.name = name
            self.content = content
            self.contentType = contentType
        }
    }

    public enum Body: Hashable, Sendable {
        case none
        case text(String)
        /// Unencoded name/value pairs.
        case urlEncoded([HeaderField])
        case multipart([MultipartPart])
        case file(path: String)
    }

    public var method: HTTPMethod
    public var url: URL
    /// User headers plus auth and Content-Type defaults (not the multipart boundary, which is generated when sending).
    public var headers: [HeaderField]
    public var body: Body
    public var settings: RequestSettings

    public init(method: HTTPMethod, url: URL, headers: [HeaderField] = [], body: Body = .none, settings: RequestSettings = RequestSettings()) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.settings = settings
    }

    public static let userAgent = "PostData/\(PostDataKit.version)"

    public static func readFile(atPath path: String) throws -> Data {
        let expanded = (path as NSString).expandingTildeInPath
        do {
            return try Data(contentsOf: URL(fileURLWithPath: expanded))
        } catch {
            throw RequestBuildError.fileNotReadable(path)
        }
    }

    /// Builds the `URLRequest`, reading any referenced files.
    public func makeURLRequest(readFile: (String) throws -> Data = ResolvedRequest.readFile(atPath:)) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.timeoutInterval = settings.timeout > 0 ? settings.timeout : 7 * 24 * 3600
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        for header in headers {
            request.addValue(header.value, forHTTPHeaderField: header.name)
        }
        switch body {
        case .none:
            break
        case .text(let text):
            request.httpBody = Data(text.utf8)
        case .urlEncoded(let pairs):
            request.httpBody = Data(RequestBuilder.formURLEncoded(pairs).utf8)
        case .multipart(let parts):
            let encoder = MultipartEncoder()
            request.httpBody = try encoder.encode(parts, readFile: readFile)
            let existing = headers.value(for: "Content-Type")
            if existing == nil || existing?.contains("boundary=") == false {
                request.setValue(encoder.contentType, forHTTPHeaderField: "Content-Type")
            }
        case .file(let path):
            request.httpBody = try readFile(path)
        }
        if !headers.contains(name: "User-Agent") {
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        }
        if !headers.contains(name: "Accept") {
            request.setValue("*/*", forHTTPHeaderField: "Accept")
        }
        return request
    }
}

public enum RequestBuilder {
    /// Substitutes variables, applies auth and fills in default headers.
    /// - Parameter auth: the effective auth (already resolved through inheritance); `.inherit` is treated as none.
    public static func resolve(_ request: HTTPRequest, auth: Auth, variables: VariableResolver) throws -> ResolvedRequest {
        var urlString = variables.resolve(request.url).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlString.isEmpty else { throw RequestBuildError.emptyURL }
        if !urlString.contains("://") {
            urlString = "http://" + urlString
        }

        var headers = request.headers.active.map {
            HeaderField(variables.resolve($0.key), variables.resolve($0.value))
        }

        func setHeader(_ name: String, _ value: String) {
            headers.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            headers.append(HeaderField(name, value))
        }

        switch auth.kind {
        case .inherit, .none:
            break
        case .bearer:
            let token = variables.resolve(auth.bearerToken)
            if !token.isEmpty { setHeader("Authorization", "Bearer \(token)") }
        case .basic:
            let credentials = variables.resolve(auth.basicUsername) + ":" + variables.resolve(auth.basicPassword)
            setHeader("Authorization", "Basic \(Data(credentials.utf8).base64EncodedString())")
        case .apiKey:
            let name = variables.resolve(auth.apiKeyName)
            let value = variables.resolve(auth.apiKeyValue)
            if !name.isEmpty {
                switch auth.apiKeyLocation {
                case .header:
                    setHeader(name, value)
                case .query:
                    urlString = appendingQueryItem(name: name, value: value, to: urlString)
                }
            }
        }

        guard let url = URL(string: urlString, encodingInvalidCharacters: true) else {
            throw RequestBuildError.invalidURL(urlString)
        }
        let scheme = url.scheme?.lowercased() ?? ""
        guard scheme == "http" || scheme == "https" else {
            throw RequestBuildError.unsupportedScheme(scheme)
        }
        // An unresolved `{{variable}}` in the host would otherwise fail later with an obscure DNS error.
        guard let host = url.host(percentEncoded: false), !host.isEmpty, !host.contains("{"), !host.contains("}") else {
            throw RequestBuildError.invalidURL(urlString)
        }

        var body = ResolvedRequest.Body.none
        var defaultContentType: String?
        if request.method.allowsBody {
            switch request.body.mode {
            case .none:
                break
            case .raw:
                body = .text(variables.resolve(request.body.raw))
                defaultContentType = request.body.rawLanguage.contentType
            case .urlEncoded:
                body = .urlEncoded(request.body.urlEncoded.active.map {
                    HeaderField(variables.resolve($0.key), variables.resolve($0.value))
                })
                defaultContentType = "application/x-www-form-urlencoded"
            case .formData:
                body = .multipart(request.body.formData.filter { $0.isEnabled && !$0.key.isEmpty }.compactMap { field in
                    let name = variables.resolve(field.key)
                    let contentType = field.contentType.map(variables.resolve).flatMap { $0.isEmpty ? nil : $0 }
                    switch field.kind {
                    case .text:
                        return .init(name: name, content: .text(variables.resolve(field.value)), contentType: contentType)
                    case .file:
                        guard let path = field.filePath, !path.isEmpty else { return nil }
                        return .init(name: name, content: .file(path: path), contentType: contentType)
                    }
                })
            case .binary:
                if let path = request.body.binaryFilePath, !path.isEmpty {
                    body = .file(path: path)
                    defaultContentType = MultipartEncoder.mimeType(forPath: path)
                }
            }
        }
        if let defaultContentType, !headers.contains(name: "Content-Type") {
            headers.append(HeaderField("Content-Type", defaultContentType))
        }

        return ResolvedRequest(method: request.method, url: url, headers: headers, body: body, settings: request.settings)
    }

    // MARK: Encoding

    private static let formAllowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._*")

    /// application/x-www-form-urlencoded encoding of a single component (space becomes `+`).
    public static func formURLEncode(_ string: String) -> String {
        (string.addingPercentEncoding(withAllowedCharacters: formAllowed) ?? string)
            .replacingOccurrences(of: "%20", with: "+")
    }

    public static func formURLEncoded(_ pairs: [HeaderField]) -> String {
        pairs.map { formURLEncode($0.name) + "=" + formURLEncode($0.value) }.joined(separator: "&")
    }

    private static let queryComponentAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&=+#")
        return set
    }()

    static func appendingQueryItem(name: String, value: String, to url: String) -> String {
        let (base, query, fragment) = URLQuerySync.split(url)
        let encodedName = name.addingPercentEncoding(withAllowedCharacters: queryComponentAllowed) ?? name
        let encodedValue = value.addingPercentEncoding(withAllowedCharacters: queryComponentAllowed) ?? value
        var result = base + "?"
        if let query, !query.isEmpty { result += query + "&" }
        result += encodedName + "=" + encodedValue
        if let fragment { result += "#" + fragment }
        return result
    }
}
