import Foundation
import Testing
@testable import PostDataKit

@Suite("JSONFormatter")
struct JSONFormatterTests {
    @Test func prettyPrintPreservesOrderAndPrecision() {
        let input = #"{"z":1,"a":[1,2.50,{"k":null}],"big":12345678901234567890,"e":-1.5E+10,"s":"a\"b\u00e9","empty":{},"list":[]}"#
        let expected = """
        {
          "z": 1,
          "a": [
            1,
            2.50,
            {
              "k": null
            }
          ],
          "big": 12345678901234567890,
          "e": -1.5E+10,
          "s": "a\\"b\\u00e9",
          "empty": {},
          "list": []
        }
        """
        #expect(JSONFormatter.prettyPrint(input) == expected)
        #expect(JSONFormatter.minify(expected) == input)
    }

    @Test func rejectsInvalidJSON() {
        for text in ["", "{", "{\"a\":}", "[1,]", "{'a':1}", "01", "1.", "tru", "\"a\nb\"", "{} x", "[\"\\q\"]"] {
            #expect(JSONFormatter.prettyPrint(text) == nil, "\(text)")
        }
        #expect(JSONFormatter.isValid(" \n[true, false, null, -0, 0.1e-2] \n"))
    }

    @Test func tokenizerFindsKindsWithUTF16Offsets() {
        let text = #"{"é":"v","n":-1.5,"b":true}"#
        let tokens = JSONTokenizer.tokenize(text)
        let ns = text as NSString
        let pieces = tokens.map { ($0.kind, ns.substring(with: NSRange(location: $0.location, length: $0.length))) }
        #expect(pieces.filter { $0.0 == .key }.map(\.1) == [#""é""#, #""n""#, #""b""#])
        #expect(pieces.filter { $0.0 == .string }.map(\.1) == [#""v""#])
        #expect(pieces.filter { $0.0 == .number }.map(\.1) == ["-1.5"])
        #expect(pieces.filter { $0.0 == .keyword }.map(\.1) == ["true"])
    }

    @Test func variableTokens() {
        let text = "a {{x}} b {{ y }} {{bad\n}}"
        let ns = text as NSString
        let found = JSONTokenizer.variableTokens(in: text).map { ns.substring(with: NSRange(location: $0.location, length: $0.length)) }
        #expect(found == ["{{x}}", "{{ y }}"])
    }

    @Test func responseContentDetection() {
        func make(_ body: String, _ type: String?) -> ResponseContent {
            ResponseContent.make(from: HTTPResponse(
                statusCode: 200,
                headers: type.map { [HeaderField("Content-Type", $0)] } ?? [],
                body: Data(body.utf8),
                duration: 0
            ))
        }
        #expect(make(#"{"a":1}"#, "application/json; charset=utf-8").kind == .json)
        #expect(make(#"{"a":1}"#, nil).kind == .json)
        #expect(make("not json", "application/json").kind == .text)
        #expect(make("<html></html>", "text/html").kind == .html)
        #expect(make("<a/>", "application/xml").kind == .xml)
        #expect(ResponseContent.make(from: HTTPResponse(statusCode: 200, headers: [], body: Data([0, 1, 2, 255]), duration: 0)).kind == .binary)
        #expect(ResponseContent.make(from: HTTPResponse(statusCode: 200, headers: [HeaderField("Content-Type", "image/png")], body: Data([1]), duration: 0)).kind == .image)
    }

    @Test func charsetDecoding() {
        let latin1 = Data([0x63, 0x61, 0x66, 0xE9]) // "café" in ISO-8859-1
        let response = HTTPResponse(statusCode: 200, headers: [HeaderField("Content-Type", "text/plain; charset=\"ISO-8859-1\"")], body: latin1, duration: 0)
        #expect(response.bodyText == "café")
        #expect(HTTPStatus.reasonPhrase(for: 404) == "Not Found")
    }
}

@Suite("WorkspaceStorage")
struct WorkspaceStorageTests {
    func makeStorage() -> (WorkspaceStorage, URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "PostDataTests-\(UUID().uuidString)")
        return (WorkspaceStorage(rootURL: root), root)
    }

    @Test func roundTripsEverything() throws {
        let (storage, root) = makeStorage()
        defer { try? FileManager.default.removeItem(at: root) }

        let request = HTTPRequest(name: "r", method: .post, url: "https://x.dev", body: .json("{}"))
        let collection = RequestCollection(name: "C", items: [.folder(Folder(name: "F", items: [.request(request)]))])
        try storage.saveCollection(collection)
        #expect(storage.loadCollections() == [collection])

        let environments = EnvironmentsState(
            globals: APIEnvironment(name: "Globals", variables: [KeyValue(key: "g", value: "1")]),
            environments: [APIEnvironment(name: "Dev")],
            activeEnvironmentID: nil
        )
        try storage.saveEnvironments(environments)
        #expect(storage.loadEnvironments() == environments)

        let entry = HistoryEntry(date: Date(timeIntervalSince1970: 1_700_000_000), request: request, statusCode: 201, duration: 0.25, size: 10)
        try storage.saveHistory([entry])
        #expect(storage.loadHistory() == [entry])

        let session = SessionSnapshot(tabs: [.init(kind: .request, request: request, collectionID: collection.id)], selectedIndex: 0, expandedItemIDs: [collection.id])
        try storage.saveSession(session)
        #expect(storage.loadSession() == session)

        try storage.deleteCollection(id: collection.id)
        #expect(storage.loadCollections().isEmpty)

        let raw = try String(contentsOf: root.appending(path: "history.json"), encoding: .utf8)
        #expect(raw.contains("\"version\" : 1"))
    }

    @Test func skipsCorruptFilesAndNewerVersions() throws {
        let (storage, root) = makeStorage()
        defer { try? FileManager.default.removeItem(at: root) }
        try storage.saveCollection(RequestCollection(name: "Good"))
        let dir = root.appending(path: "collections")
        try Data("garbage".utf8).write(to: dir.appending(path: "bad.json"))
        try Data(#"{"version":99,"data":{"name":"Future"}}"#.utf8).write(to: dir.appending(path: "future.json"))
        #expect(storage.loadCollections().map(\.name) == ["Good"])
        #expect(storage.loadEnvironments() == nil)
        #expect(storage.loadHistory().isEmpty)
    }
}
