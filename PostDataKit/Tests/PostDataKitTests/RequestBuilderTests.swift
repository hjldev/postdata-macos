import Foundation
import Testing
@testable import PostDataKit

@Suite("RequestBuilder")
struct RequestBuilderTests {
    let variables = VariableResolver(environment: [
        KeyValue(key: "base", value: "https://api.example.com"),
        KeyValue(key: "token", value: "t0k"),
        KeyValue(key: "name", value: "Ada Lovelace"),
    ])

    @Test func resolvesURLHeadersAndDefaults() throws {
        let request = HTTPRequest(
            method: .post,
            url: "{{base}}/users?q={{name}}",
            headers: [
                KeyValue(key: "X-Trace", value: "{{token}}"),
                KeyValue(key: "X-Off", value: "1", isEnabled: false),
                KeyValue(key: "", value: "no key"),
            ],
            body: .json(#"{"name":"{{name}}"}"#)
        )
        let resolved = try RequestBuilder.resolve(request, auth: .none, variables: variables)
        #expect(resolved.url.absoluteString == "https://api.example.com/users?q=Ada%20Lovelace")
        #expect(resolved.headers == [HeaderField("X-Trace", "t0k"), HeaderField("Content-Type", "application/json")])
        #expect(resolved.body == .text(#"{"name":"Ada Lovelace"}"#))

        let urlRequest = try resolved.makeURLRequest()
        #expect(urlRequest.httpMethod == "POST")
        #expect(urlRequest.value(forHTTPHeaderField: "User-Agent") == ResolvedRequest.userAgent)
        #expect(urlRequest.value(forHTTPHeaderField: "Accept") == "*/*")
        #expect(urlRequest.httpBody == Data(#"{"name":"Ada Lovelace"}"#.utf8))
    }

    @Test func userContentTypeIsNotOverridden() throws {
        let request = HTTPRequest(method: .post, url: "x.dev", headers: [KeyValue(key: "content-type", value: "text/csv")], body: .json("a,b"))
        let resolved = try RequestBuilder.resolve(request, auth: .none, variables: .empty)
        #expect(resolved.url.absoluteString == "http://x.dev")
        #expect(resolved.headers == [HeaderField("content-type", "text/csv")])
    }

    @Test func authKinds() throws {
        let request = HTTPRequest(url: "{{base}}/me", headers: [KeyValue(key: "Authorization", value: "manual")])
        let bearer = try RequestBuilder.resolve(request, auth: .bearer("{{token}}"), variables: variables)
        #expect(bearer.headers == [HeaderField("Authorization", "Bearer t0k")])

        let basic = try RequestBuilder.resolve(request, auth: .basic(username: "ada", password: "pw"), variables: variables)
        #expect(basic.headers.value(for: "authorization") == "Basic YWRhOnB3")

        let headerKey = try RequestBuilder.resolve(request, auth: .apiKey(name: "X-Key", value: "{{token}}"), variables: variables)
        #expect(headerKey.headers.value(for: "X-Key") == "t0k")

        let queryKey = try RequestBuilder.resolve(
            HTTPRequest(url: "{{base}}/me?a=1#f"),
            auth: .apiKey(name: "api key", value: "a&b", location: .query),
            variables: variables
        )
        #expect(queryKey.url.absoluteString == "https://api.example.com/me?a=1&api%20key=a%26b#f")
    }

    @Test func urlEncodedBody() throws {
        var request = HTTPRequest(method: .post, url: "https://x.dev")
        request.body.mode = .urlEncoded
        request.body.urlEncoded = [
            KeyValue(key: "name", value: "{{name}}"),
            KeyValue(key: "math", value: "1+1=2&"),
            KeyValue(key: "off", value: "x", isEnabled: false),
        ]
        let resolved = try RequestBuilder.resolve(request, auth: .none, variables: variables)
        #expect(resolved.headers.value(for: "Content-Type") == "application/x-www-form-urlencoded")
        let body = try #require(try resolved.makeURLRequest().httpBody)
        #expect(String(decoding: body, as: UTF8.self) == "name=Ada+Lovelace&math=1%2B1%3D2%26")
    }

    @Test func bodyIsDroppedForGET() throws {
        let request = HTTPRequest(method: .get, url: "https://x.dev", body: .json("{}"))
        let resolved = try RequestBuilder.resolve(request, auth: .none, variables: .empty)
        #expect(resolved.body == .none)
        #expect(resolved.headers.isEmpty)
    }

    @Test func multipartEncoding() throws {
        var request = HTTPRequest(method: .post, url: "https://x.dev/upload")
        request.body.mode = .formData
        request.body.formData = [
            FormDataField(key: "caption", value: "hi \"there\""),
            FormDataField(key: "file", kind: .file, filePath: "/tmp/photo.png"),
            FormDataField(key: "empty-file", kind: .file),
        ]
        let resolved = try RequestBuilder.resolve(request, auth: .none, variables: .empty)
        guard case .multipart(let parts) = resolved.body else {
            Issue.record("expected multipart")
            return
        }
        #expect(parts.count == 2)

        let encoder = MultipartEncoder(boundary: "XYZ")
        let data = try encoder.encode(parts) { path in
            #expect(path == "/tmp/photo.png")
            return Data("PNGDATA".utf8)
        }
        let expected = [
            "--XYZ",
            "Content-Disposition: form-data; name=\"caption\"",
            "",
            "hi \"there\"",
            "--XYZ",
            "Content-Disposition: form-data; name=\"file\"; filename=\"photo.png\"",
            "Content-Type: image/png",
            "",
            "PNGDATA",
            "--XYZ--",
            "",
        ].joined(separator: "\r\n")
        #expect(String(decoding: data, as: UTF8.self) == expected)

        let urlRequest = try resolved.makeURLRequest { _ in Data() }
        #expect(urlRequest.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
    }

    @Test func errors() {
        #expect(throws: RequestBuildError.emptyURL) {
            try RequestBuilder.resolve(HTTPRequest(url: "  "), auth: .none, variables: .empty)
        }
        #expect(throws: RequestBuildError.unsupportedScheme("ftp")) {
            try RequestBuilder.resolve(HTTPRequest(url: "ftp://x.dev"), auth: .none, variables: .empty)
        }
        #expect(throws: RequestBuildError.invalidURL("http://{{missing}}/x")) {
            try RequestBuilder.resolve(HTTPRequest(url: "{{missing}}/x"), auth: .none, variables: .empty)
        }
    }
}
