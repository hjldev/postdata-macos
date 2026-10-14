import Foundation
import Testing
@testable import PostDataKit

@Suite("ShellTokenizer")
struct ShellTokenizerTests {
    @Test func quotingRules() throws {
        let tokens = try ShellTokenizer.tokenize(#"curl 'a b' "c \"d\" \$e" f\ g $'h\ni\x41é' "x"'y'z"#)
        #expect(tokens == ["curl", "a b", "c \"d\" $e", "f g", "h\niAé", "xyz"])
    }

    @Test func lineContinuations() throws {
        let tokens = try ShellTokenizer.tokenize("curl \\\n  -X POST \\\r\n  'https://x.dev'")
        #expect(tokens == ["curl", "-X", "POST", "https://x.dev"])
    }

    @Test func unterminatedQuoteThrows() {
        #expect(throws: ShellTokenizerError.unterminatedQuote) { try ShellTokenizer.tokenize("curl 'oops") }
    }

    @Test func quoteRoundTrips() throws {
        for word in ["simple", "has space", "it's", "", "a\"b", "{{var}}", "中文"] {
            #expect(try ShellTokenizer.tokenize("x " + ShellTokenizer.quote(word)) == ["x", word])
        }
    }
}

@Suite("CurlParser")
struct CurlParserTests {
    @Test func chromeStyleJSONPost() throws {
        let command = """
        curl 'https://api.example.com/v1/users?page=2' \\
          -H 'accept: application/json' \\
          -H 'content-type: application/json' \\
          -H 'authorization: Bearer abc' \\
          --data-raw '{"name":"Ada","tags":["a","b"]}' \\
          --compressed
        """
        let request = try CurlParser.parse(command)
        #expect(request.method == .post)
        #expect(request.url == "https://api.example.com/v1/users?page=2")
        #expect(request.queryParams.map(\.key) == ["page"])
        #expect(request.headers.map(\.key) == ["accept", "content-type", "authorization"])
        #expect(request.body.mode == .raw)
        #expect(request.body.rawLanguage == .json)
        #expect(JSONFormatter.minify(request.body.raw) == #"{"name":"Ada","tags":["a","b"]}"#)
        #expect(request.name == "/v1/users")
    }

    @Test func combinedShortFlagsAndAttachedValues() throws {
        let request = try CurlParser.parse("curl -sSkL -XDELETE -H'X-A: 1' https://x.dev/item/1 -u ada:pw")
        #expect(request.method == .delete)
        #expect(request.settings.validateSSL == false)
        #expect(request.headers == [KeyValue(id: request.headers[0].id, key: "X-A", value: "1")])
        #expect(request.auth.kind == .basic)
        #expect(request.auth.basicUsername == "ada")
        #expect(request.auth.basicPassword == "pw")
    }

    @Test func formURLEncodedData() throws {
        let request = try CurlParser.parse("curl https://x.dev/login -d 'user=ada+l' -d 'pass=a%26b' --data-urlencode 'note=x y'")
        #expect(request.method == .post)
        #expect(request.body.mode == .urlEncoded)
        #expect(request.body.urlEncoded.map(\.key) == ["user", "pass", "note"])
        #expect(request.body.urlEncoded.map(\.value) == ["ada l", "a&b", "x y"])
    }

    @Test func multipartForm() throws {
        let request = try CurlParser.parse(#"curl -F 'file=@"/tmp/a b.png";type=image/png' -F name=ada --form-string 'raw=@literal' https://x.dev/up"#)
        #expect(request.method == .post)
        #expect(request.body.mode == .formData)
        let fields = request.body.formData
        #expect(fields.count == 3)
        #expect(fields[0].kind == .file)
        #expect(fields[0].filePath == "/tmp/a b.png")
        #expect(fields[0].contentType == "image/png")
        #expect(fields[1].kind == .text && fields[1].value == "ada")
        #expect(fields[2].kind == .text && fields[2].value == "@literal")
    }

    @Test func getWithDataAppendsQuery() throws {
        let request = try CurlParser.parse("curl -G https://x.dev/search -d q=swift -d n=1")
        #expect(request.method == .get)
        #expect(request.url == "https://x.dev/search?q=swift&n=1")
        #expect(request.body.mode == .none)
    }

    @Test func binaryFileAndHead() throws {
        let upload = try CurlParser.parse("curl --data-binary @/tmp/blob.bin -X PUT https://x.dev/blob")
        #expect(upload.method == .put)
        #expect(upload.body.mode == .binary)
        #expect(upload.body.binaryFilePath == "/tmp/blob.bin")

        let head = try CurlParser.parse("curl -I https://x.dev")
        #expect(head.method == .head)
    }

    @Test func valueFlagsDoNotSwallowURL() throws {
        let request = try CurlParser.parse("curl --max-time 5 -o out.txt --retry 3 https://x.dev/a --cookie 'sid=1'")
        #expect(request.url == "https://x.dev/a")
        #expect(request.settings.timeout == 5)
        #expect(request.headers.map(\.key) == ["Cookie"])
    }

    @Test func rejectsNonCurl() {
        #expect(throws: CurlParseError.notCurlCommand) { try CurlParser.parse("wget https://x.dev") }
        #expect(throws: CurlParseError.missingURL) { try CurlParser.parse("curl -X POST") }
        #expect(CurlParser.looksLikeCurl("  curl https://x"))
        #expect(CurlParser.looksLikeCurl("$ curl https://x"))
        #expect(!CurlParser.looksLikeCurl("https://curl.se"))
    }
}

@Suite("CodeGenerators")
struct CodeGeneratorTests {
    func sample() throws -> ResolvedRequest {
        var request = HTTPRequest(
            method: .post,
            url: "https://api.example.com/users?x=1",
            headers: [KeyValue(key: "X-Quote", value: "it's \"q\"")],
            body: .json("{\n  \"name\": \"Ada\"\n}"),
            auth: .bearer("tok")
        )
        request.settings.followRedirects = false
        return try RequestBuilder.resolve(request, auth: request.auth, variables: .empty)
    }

    @Test func curlRoundTrip() throws {
        let resolved = try sample()
        let code = CurlGenerator().generate(resolved)
        let parsed = try CurlParser.parse(code)
        #expect(parsed.method == .post)
        #expect(parsed.url == "https://api.example.com/users?x=1")
        #expect(parsed.headers.map(\.key) == ["X-Quote", "Authorization", "Content-Type"])
        #expect(parsed.headers.first?.value == "it's \"q\"")
        #expect(JSONFormatter.minify(parsed.body.raw) == #"{"name":"Ada"}"#)
        #expect(!code.contains("--location"))
    }

    @Test func curlRoundTripForForms() throws {
        var request = HTTPRequest(method: .post, url: "https://x.dev/f")
        request.body.mode = .urlEncoded
        request.body.urlEncoded = [KeyValue(key: "a b", value: "1&2")]
        let urlEncoded = try CurlParser.parse(CurlGenerator().generate(try RequestBuilder.resolve(request, auth: .none, variables: .empty)))
        #expect(urlEncoded.body.mode == .urlEncoded)
        #expect(urlEncoded.body.urlEncoded.map(\.key) == ["a b"])
        #expect(urlEncoded.body.urlEncoded.map(\.value) == ["1&2"])

        request.body.mode = .formData
        request.body.formData = [FormDataField(key: "t", value: "@not-a-file"), FormDataField(key: "f", kind: .file, filePath: "/tmp/x.txt")]
        let form = try CurlParser.parse(CurlGenerator().generate(try RequestBuilder.resolve(request, auth: .none, variables: .empty)))
        #expect(form.body.formData.map(\.kind) == [.text, .file])
        #expect(form.body.formData[0].value == "@not-a-file")
        #expect(form.body.formData[1].filePath == "/tmp/x.txt")
    }

    @Test func allGeneratorsProduceOutput() throws {
        let resolved = try sample()
        for generator in CodeGenerators.all {
            let code = generator.generate(resolved)
            #expect(code.contains("https://api.example.com/users?x=1"), "\(generator.id)")
            #expect(code.contains("Bearer tok"), "\(generator.id)")
        }
        let swift = SwiftURLSessionGenerator().generate(resolved)
        #expect(swift.contains(#"request.addValue("it's \"q\"", forHTTPHeaderField: "X-Quote")"#))
        #expect(swift.contains("\"\"\"\n{\n  \"name\": \"Ada\"\n}\n\"\"\""))
        let python = PythonRequestsGenerator().generate(resolved)
        #expect(python.contains("allow_redirects=False"))
        let js = JavaScriptFetchGenerator().generate(resolved)
        #expect(js.contains(#"const raw = JSON.stringify({"name":"Ada"});"#))
        #expect(js.contains(#"redirect: "manual""#))
    }
}
