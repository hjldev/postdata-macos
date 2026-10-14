import Foundation
import Synchronization

public enum HTTPClientError: LocalizedError {
    case notHTTPResponse

    public var errorDescription: String? {
        switch self {
        case .notHTTPResponse: "服务器返回的不是 HTTP 响应"
        }
    }
}

/// Sends requests with per-request redirect and TLS settings, collecting timing metrics.
///
/// Sessions are cached (one per TLS-validation setting) so connections are kept alive and
/// reused across requests, like a browser or Postman. Redirect policy, redirect tracking and
/// metrics are handled per task. Cookies go through `HTTPCookieStorage.shared`, acting as a cookie jar.
public final class HTTPClient: Sendable {
    private let makeConfiguration: @Sendable () -> URLSessionConfiguration
    private let sessions = Mutex<[Bool: URLSession]>([:])

    /// - Parameter configuration: a factory for the session configuration; tests inject `URLProtocol` stubs here.
    public init(configuration: @escaping @Sendable () -> URLSessionConfiguration = { .ephemeral }) {
        self.makeConfiguration = configuration
    }

    deinit {
        for session in sessions.withLock({ Array($0.values) }) {
            session.invalidateAndCancel()
        }
    }

    @concurrent
    public func send(_ resolved: ResolvedRequest) async throws -> HTTPResponse {
        let request = try resolved.makeURLRequest()
        return try await send(request, followRedirects: resolved.settings.followRedirects, validateSSL: resolved.settings.validateSSL)
    }

    @concurrent
    public func send(_ request: URLRequest, followRedirects: Bool, validateSSL: Bool) async throws -> HTTPResponse {
        let session = session(validateSSL: validateSSL)
        let tracker = TaskTracker(followRedirects: followRedirects)

        let clock = ContinuousClock()
        let start = clock.now
        let (received, response) = try await session.data(for: request, delegate: tracker)
        let elapsed = start.duration(to: clock.now)
        // URLSession grows its buffer while downloading, so large bodies can hold ~2x their size;
        // keep an exact-size copy since responses stay in memory while their tab is open.
        let data = received.count >= 64 * 1024 ? received.withUnsafeBytes { Data($0) } : received
        let duration = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18

        guard let http = response as? HTTPURLResponse else { throw HTTPClientError.notHTTPResponse }

        var headerFields: [String: String] = [:]
        var headers: [HeaderField] = []
        for (key, value) in http.allHeaderFields {
            let name = String(describing: key)
            let text = String(describing: value)
            headerFields[name] = text
            headers.append(HeaderField(name, text))
        }
        headers.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let cookies = http.url.map { HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: $0) } ?? []
        let (timings, redirects) = tracker.result()

        return HTTPResponse(
            statusCode: http.statusCode,
            headers: headers,
            body: data,
            mimeType: http.mimeType,
            textEncodingName: http.textEncodingName,
            url: http.url,
            duration: timings?.total ?? duration,
            timings: timings,
            cookies: cookies.map(ResponseCookie.init),
            redirects: redirects
        )
    }

    /// One long-lived session per TLS-validation setting, so connections are reused.
    private func session(validateSSL: Bool) -> URLSession {
        sessions.withLock { cache in
            if let session = cache[validateSSL] { return session }
            let configuration = makeConfiguration()
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            configuration.httpCookieStorage = .shared
            configuration.httpShouldSetCookies = true
            configuration.httpCookieAcceptPolicy = .always
            // Each URLRequest carries its own timeout; don't let the session impose a shorter one.
            configuration.timeoutIntervalForRequest = 7 * 24 * 3600
            configuration.timeoutIntervalForResource = 7 * 24 * 3600
            let session = URLSession(configuration: configuration, delegate: SessionDelegate(validateSSL: validateSSL), delegateQueue: nil)
            cache[validateSSL] = session
            return session
        }
    }
}

/// Session-level: server trust, which URLSession only asks the session delegate about.
private final class SessionDelegate: NSObject, URLSessionDelegate, Sendable {
    let validateSSL: Bool

    init(validateSSL: Bool) {
        self.validateSSL = validateSSL
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        if !validateSSL,
           challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            return (.useCredential, URLCredential(trust: trust))
        }
        return (.performDefaultHandling, nil)
    }
}

/// Task-level: redirect policy, the redirect chain and timing metrics for one request.
private final class TaskTracker: NSObject, URLSessionTaskDelegate, Sendable {
    let followRedirects: Bool
    private struct State {
        var redirects: [RedirectHop] = []
        var metrics: URLSessionTaskMetrics?
    }
    private let state = Mutex(State())

    init(followRedirects: Bool) {
        self.followRedirects = followRedirects
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        guard followRedirects else { return nil }
        let hop = RedirectHop(url: response.url, statusCode: response.statusCode, location: request.url?.absoluteString)
        state.withLock { $0.redirects.append(hop) }
        return request
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        state.withLock { $0.metrics = metrics }
    }

    func result() -> (RequestTimings?, [RedirectHop]) {
        state.withLock { state in
            var redirects = state.redirects
            guard let metrics = state.metrics else { return (nil, redirects) }
            // Attach per-hop durations: network transactions line up with the redirect chain.
            let transactions = metrics.transactionMetrics.filter { $0.resourceFetchType == .networkLoad }
            if transactions.count == redirects.count + 1 {
                for index in redirects.indices {
                    redirects[index].duration = Self.span(transactions[index].fetchStartDate, transactions[index].responseEndDate)
                }
            }
            return (Self.timings(from: metrics), redirects)
        }
    }

    private static func span(_ start: Date?, _ end: Date?) -> TimeInterval? {
        guard let start, let end else { return nil }
        return max(0, end.timeIntervalSince(start))
    }

    /// Phase breakdown of the final hop; `total` covers the whole task including redirects.
    static func timings(from metrics: URLSessionTaskMetrics) -> RequestTimings {
        var timings = RequestTimings(total: metrics.taskInterval.duration)
        guard let transaction = metrics.transactionMetrics.last(where: { $0.resourceFetchType == .networkLoad })
            ?? metrics.transactionMetrics.last else {
            return timings
        }
        timings.dnsLookup = span(transaction.domainLookupStartDate, transaction.domainLookupEndDate)
        let tls = span(transaction.secureConnectionStartDate, transaction.secureConnectionEndDate)
        timings.tlsHandshake = tls
        if let connect = span(transaction.connectStartDate, transaction.connectEndDate) {
            timings.tcpConnect = max(0, connect - (tls ?? 0))
        }
        timings.requestSent = span(transaction.requestStartDate, transaction.requestEndDate)
        timings.waiting = span(transaction.requestEndDate, transaction.responseStartDate)
        timings.download = span(transaction.responseStartDate, transaction.responseEndDate)
        timings.isReusedConnection = transaction.isReusedConnection
        return timings
    }
}
