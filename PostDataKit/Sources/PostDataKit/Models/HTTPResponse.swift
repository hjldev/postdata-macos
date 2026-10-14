import Foundation

public struct HeaderField: Hashable, Sendable, Codable {
    public var name: String
    public var value: String

    public init(_ name: String, _ value: String) {
        self.name = name
        self.value = value
    }
}

extension Array where Element == HeaderField {
    /// Case-insensitive header lookup (first match).
    public func value(for name: String) -> String? {
        first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    public func contains(name: String) -> Bool {
        value(for: name) != nil
    }
}

/// Phase durations of a request, from `URLSessionTaskMetrics`. Nil phases did not happen
/// (e.g. DNS and connect on a reused connection).
public struct RequestTimings: Hashable, Sendable {
    public var dnsLookup: TimeInterval?
    public var tcpConnect: TimeInterval?
    public var tlsHandshake: TimeInterval?
    public var requestSent: TimeInterval?
    public var waiting: TimeInterval?
    public var download: TimeInterval?
    /// Total for the whole request, including any redirect hops.
    public var total: TimeInterval
    /// The final hop ran on a kept-alive connection, so it had no DNS / TCP / TLS phases.
    public var isReusedConnection: Bool

    public init(
        dnsLookup: TimeInterval? = nil,
        tcpConnect: TimeInterval? = nil,
        tlsHandshake: TimeInterval? = nil,
        requestSent: TimeInterval? = nil,
        waiting: TimeInterval? = nil,
        download: TimeInterval? = nil,
        total: TimeInterval,
        isReusedConnection: Bool = false
    ) {
        self.dnsLookup = dnsLookup
        self.tcpConnect = tcpConnect
        self.tlsHandshake = tlsHandshake
        self.requestSent = requestSent
        self.waiting = waiting
        self.download = download
        self.total = total
        self.isReusedConnection = isReusedConnection
    }
}

/// A redirect that was followed on the way to the final response.
public struct RedirectHop: Hashable, Sendable {
    public var url: URL?
    public var statusCode: Int
    /// Where the redirect pointed.
    public var location: String?
    public var duration: TimeInterval?

    public init(url: URL?, statusCode: Int, location: String?, duration: TimeInterval? = nil) {
        self.url = url
        self.statusCode = statusCode
        self.location = location
        self.duration = duration
    }
}

public struct ResponseCookie: Hashable, Sendable, Identifiable {
    public var id: String { "\(domain)|\(path)|\(name)" }
    public var name: String
    public var value: String
    public var domain: String
    public var path: String
    public var expires: Date?
    public var isHTTPOnly: Bool
    public var isSecure: Bool

    public init(name: String, value: String, domain: String, path: String, expires: Date?, isHTTPOnly: Bool, isSecure: Bool) {
        self.name = name
        self.value = value
        self.domain = domain
        self.path = path
        self.expires = expires
        self.isHTTPOnly = isHTTPOnly
        self.isSecure = isSecure
    }

    public init(_ cookie: HTTPCookie) {
        self.init(
            name: cookie.name,
            value: cookie.value,
            domain: cookie.domain,
            path: cookie.path,
            expires: cookie.expiresDate,
            isHTTPOnly: cookie.isHTTPOnly,
            isSecure: cookie.isSecure
        )
    }
}

public struct HTTPResponse: Hashable, Sendable {
    public var statusCode: Int
    /// Sorted by name: URLSession does not preserve the wire order of headers.
    public var headers: [HeaderField]
    public var body: Data
    public var mimeType: String?
    public var textEncodingName: String?
    public var url: URL?
    public var duration: TimeInterval
    public var timings: RequestTimings?
    public var cookies: [ResponseCookie]
    /// Redirects followed before this response, in order.
    public var redirects: [RedirectHop]

    public init(
        statusCode: Int,
        headers: [HeaderField],
        body: Data,
        mimeType: String? = nil,
        textEncodingName: String? = nil,
        url: URL? = nil,
        duration: TimeInterval,
        timings: RequestTimings? = nil,
        cookies: [ResponseCookie] = [],
        redirects: [RedirectHop] = []
    ) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
        self.mimeType = mimeType
        self.textEncodingName = textEncodingName
        self.url = url
        self.duration = duration
        self.timings = timings
        self.cookies = cookies
        self.redirects = redirects
    }

    public var bodySize: Int { body.count }

    /// Approximate size of the header block on the wire.
    public var headersSize: Int {
        headers.reduce(0) { $0 + $1.name.utf8.count + $1.value.utf8.count + 4 }
    }

    public var statusText: String { HTTPStatus.reasonPhrase(for: statusCode) }

    public var contentType: String? { headers.value(for: "Content-Type") ?? mimeType }

    /// Body decoded with the declared charset, falling back to UTF-8 then Latin-1.
    public var bodyText: String? { TextDecoding.decode(body, charset: textEncodingName ?? TextDecoding.charset(fromContentType: contentType)) }
}

public enum TextDecoding {
    public static func charset(fromContentType contentType: String?) -> String? {
        guard let contentType else { return nil }
        for part in contentType.split(separator: ";") {
            let pair = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if pair.count == 2, pair[0].lowercased() == "charset" {
                return pair[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
        }
        return nil
    }

    public static func decode(_ data: Data, charset: String?) -> String? {
        if let charset {
            let cfEncoding = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
            if cfEncoding != kCFStringEncodingInvalidId {
                let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
                if let text = String(data: data, encoding: encoding) { return text }
            }
        }
        if let text = String(data: data, encoding: .utf8) { return text }
        return String(data: data, encoding: .isoLatin1)
    }
}

public enum HTTPStatus {
    public static func reasonPhrase(for code: Int) -> String {
        switch code {
        case 100: "Continue"
        case 101: "Switching Protocols"
        case 200: "OK"
        case 201: "Created"
        case 202: "Accepted"
        case 203: "Non-Authoritative Information"
        case 204: "No Content"
        case 205: "Reset Content"
        case 206: "Partial Content"
        case 207: "Multi-Status"
        case 300: "Multiple Choices"
        case 301: "Moved Permanently"
        case 302: "Found"
        case 303: "See Other"
        case 304: "Not Modified"
        case 307: "Temporary Redirect"
        case 308: "Permanent Redirect"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 402: "Payment Required"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 406: "Not Acceptable"
        case 407: "Proxy Authentication Required"
        case 408: "Request Timeout"
        case 409: "Conflict"
        case 410: "Gone"
        case 411: "Length Required"
        case 412: "Precondition Failed"
        case 413: "Payload Too Large"
        case 414: "URI Too Long"
        case 415: "Unsupported Media Type"
        case 416: "Range Not Satisfiable"
        case 417: "Expectation Failed"
        case 418: "I'm a teapot"
        case 422: "Unprocessable Content"
        case 425: "Too Early"
        case 426: "Upgrade Required"
        case 428: "Precondition Required"
        case 429: "Too Many Requests"
        case 431: "Request Header Fields Too Large"
        case 451: "Unavailable For Legal Reasons"
        case 500: "Internal Server Error"
        case 501: "Not Implemented"
        case 502: "Bad Gateway"
        case 503: "Service Unavailable"
        case 504: "Gateway Timeout"
        case 505: "HTTP Version Not Supported"
        default: HTTPURLResponse.localizedString(forStatusCode: code).capitalized
        }
    }
}
