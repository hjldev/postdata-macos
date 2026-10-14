import Foundation
import Synchronization
import Testing
@testable import PostDataKit

/// Serves canned responses and records the requests it receives.
final class StubURLProtocol: URLProtocol {
    struct Stub: Sendable {
        var status: Int
        var headers: [String: String]
        var body: Data
        var redirectTo: URL?
        /// Never respond, to exercise timeouts.
        var hangs = false
    }

    static let stubs = Mutex<[String: Stub]>([:])
    static let received = Mutex<[URLRequest]>([])

    static func register(_ path: String, _ stub: Stub) {
        stubs.withLock { $0[path] = stub }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var recorded = request
        if recorded.httpBody == nil, let stream = request.httpBodyStream {
            recorded.httpBody = Self.read(stream)
        }
        Self.received.withLock { $0.append(recorded) }

        let path = request.url?.path() ?? ""
        guard let stub = Self.stubs.withLock({ $0[path] }), let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        if stub.hangs { return }
        let response = HTTPURLResponse(url: url, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: stub.headers)!
        if let target = stub.redirectTo {
            // If the session declines the redirect, the redirect response itself becomes the final response.
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

@Suite("HTTPClient", .serialized)
struct HTTPClientTests {
    let client = HTTPClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return configuration
    }

    @Test func sendsResolvedRequestAndParsesResponse() async throws {
        StubURLProtocol.register("/echo", .init(
            status: 201,
            headers: ["Content-Type": "application/json", "Set-Cookie": "sid=abc; Path=/", "X-B": "2", "X-A": "1"],
            body: Data(#"{"ok":true}"#.utf8)
        ))
        let request = HTTPRequest(method: .post, url: "https://stub.test/echo", body: .json(#"{"n":1}"#))
        let resolved = try RequestBuilder.resolve(request, auth: .bearer("t"), variables: .empty)
        let response = try await client.send(resolved)

        #expect(response.statusCode == 201)
        #expect(response.statusText == "Created")
        #expect(response.bodyText == #"{"ok":true}"#)
        #expect(response.headers.value(for: "content-type") == "application/json")
        let names = response.headers.map(\.name)
        #expect(names == names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
        #expect(response.cookies.map(\.name) == ["sid"])

        let sent = try #require(StubURLProtocol.received.withLock { $0.last })
        #expect(sent.httpMethod == "POST")
        #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer t")
        #expect(sent.httpBody == Data(#"{"n":1}"#.utf8))
    }

    @Test func redirectsCanBeDisabled() async throws {
        StubURLProtocol.register("/old", .init(status: 302, headers: ["Location": "https://stub.test/new"], body: Data(), redirectTo: URL(string: "https://stub.test/new")))
        StubURLProtocol.register("/new", .init(status: 200, headers: [:], body: Data("new".utf8)))

        var request = HTTPRequest(url: "https://stub.test/old")
        request.settings.timeout = 5
        let followed = try await client.send(try RequestBuilder.resolve(request, auth: .none, variables: .empty))
        #expect(followed.statusCode == 200)
        #expect(followed.bodyText == "new")
        #expect(followed.redirects.map(\.statusCode) == [302])
        #expect(followed.redirects.first?.url?.path() == "/old")
        #expect(followed.redirects.first?.location == "https://stub.test/new")

        request.settings.followRedirects = false
        let stopped = try await client.send(try RequestBuilder.resolve(request, auth: .none, variables: .empty))
        #expect(stopped.statusCode == 302)
        #expect(stopped.headers.value(for: "Location") == "https://stub.test/new")
        #expect(stopped.redirects.isEmpty)
    }

    /// Sessions are shared with a long session-level timeout, so the request's own timeout must still apply.
    @Test func requestTimeoutIsHonored() async throws {
        StubURLProtocol.register("/hang", .init(status: 200, headers: [:], body: Data(), hangs: true))
        var request = HTTPRequest(url: "https://stub.test/hang")
        request.settings.timeout = 1
        let resolved = try RequestBuilder.resolve(request, auth: .none, variables: .empty)
        let clock = ContinuousClock()
        let start = clock.now
        await #expect(throws: URLError.self) { try await client.send(resolved) }
        #expect(start.duration(to: clock.now) < .seconds(5))
    }

    @Test func networkErrorsPropagate() async throws {
        let request = HTTPRequest(url: "https://stub.test/missing")
        await #expect(throws: URLError.self) {
            try await client.send(try RequestBuilder.resolve(request, auth: .none, variables: .empty))
        }
    }
}
