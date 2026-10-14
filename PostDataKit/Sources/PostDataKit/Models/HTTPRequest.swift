import Foundation

public struct RequestSettings: Hashable, Sendable, Codable {
    public var followRedirects: Bool
    /// Seconds; 0 means no timeout.
    public var timeout: TimeInterval
    public var validateSSL: Bool

    public init(followRedirects: Bool = true, timeout: TimeInterval = 30, validateSSL: Bool = true) {
        self.followRedirects = followRedirects
        self.timeout = timeout
        self.validateSSL = validateSSL
    }

    private enum CodingKeys: String, CodingKey { case followRedirects, timeout, validateSSL }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        followRedirects = try c.decodeIfPresent(Bool.self, forKey: .followRedirects) ?? true
        timeout = try c.decodeIfPresent(TimeInterval.self, forKey: .timeout) ?? 30
        validateSSL = try c.decodeIfPresent(Bool.self, forKey: .validateSSL) ?? true
    }
}

/// A request as edited by the user. Variables (`{{name}}`) are left unresolved.
///
/// `url` and `queryParams` are kept in sync: `url` contains the enabled params, while
/// disabled params live only in `queryParams`. Use `setURL(_:)` / `setQueryParams(_:)`.
public struct HTTPRequest: Identifiable, Hashable, Sendable, Codable {
    public var id: UUID
    public var name: String
    public var method: HTTPMethod
    public var url: String
    public var queryParams: [KeyValue]
    public var headers: [KeyValue]
    public var body: RequestBody
    public var auth: Auth
    public var settings: RequestSettings
    public var description: String

    public init(
        id: UUID = UUID(),
        name: String = "Untitled Request",
        method: HTTPMethod = .get,
        url: String = "",
        queryParams: [KeyValue]? = nil,
        headers: [KeyValue] = [],
        body: RequestBody = RequestBody(),
        auth: Auth = .inherit,
        settings: RequestSettings = RequestSettings(),
        description: String = ""
    ) {
        self.id = id
        self.name = name
        self.method = method
        self.url = url
        self.queryParams = queryParams ?? URLQuerySync.params(fromURL: url, existing: [])
        self.headers = headers
        self.body = body
        self.auth = auth
        self.settings = settings
        self.description = description
    }

    /// Updates the URL and re-derives the query params table from it.
    public mutating func setURL(_ newURL: String) {
        url = newURL
        queryParams = URLQuerySync.params(fromURL: newURL, existing: queryParams)
    }

    /// Updates the params table and rewrites the query part of the URL.
    public mutating func setQueryParams(_ params: [KeyValue]) {
        queryParams = params
        url = URLQuerySync.url(url, replacingQueryWith: params)
    }

    /// A copy with a fresh identity, e.g. for "Duplicate" or opening history entries.
    public func withNewID(name: String? = nil) -> HTTPRequest {
        var copy = self
        copy.id = UUID()
        if let name { copy.name = name }
        return copy
    }

    /// A short name derived from the URL, used for imported or unnamed requests.
    public static func suggestedName(for url: String) -> String {
        let (base, _, _) = URLQuerySync.split(url)
        var trimmed = base
        if let range = trimmed.range(of: "://") { trimmed = String(trimmed[range.upperBound...]) }
        let path = trimmed.split(separator: "/", omittingEmptySubsequences: true).dropFirst()
        if path.isEmpty { return trimmed.isEmpty ? "Untitled Request" : trimmed }
        return "/" + path.joined(separator: "/")
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, method, url, queryParams, headers, body, auth, settings, description
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Untitled Request"
        method = try c.decodeIfPresent(HTTPMethod.self, forKey: .method) ?? .get
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        queryParams = try c.decodeIfPresent([KeyValue].self, forKey: .queryParams)
            ?? URLQuerySync.params(fromURL: url, existing: [])
        headers = try c.decodeIfPresent([KeyValue].self, forKey: .headers) ?? []
        body = try c.decodeIfPresent(RequestBody.self, forKey: .body) ?? RequestBody()
        auth = try c.decodeIfPresent(Auth.self, forKey: .auth) ?? .inherit
        settings = try c.decodeIfPresent(RequestSettings.self, forKey: .settings) ?? RequestSettings()
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
    }
}
