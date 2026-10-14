import Foundation
import Testing
@testable import PostDataKit

@Suite("Postman import/export")
struct PostmanTests {
    func fixture() throws -> Data {
        let url = try #require(Bundle.module.url(forResource: "sample.postman_collection", withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test func detectsKinds() throws {
        #expect(PostmanImporter.detect(try fixture()) == .collection)
        #expect(PostmanImporter.detect(Data(#"{"name":"Dev","values":[]}"#.utf8)) == .environment)
        #expect(PostmanImporter.detect(Data("nope".utf8)) == .unknown)
    }

    @Test func importsCollection() throws {
        let result = try PostmanImporter.importCollection(from: try fixture())
        let collection = result.collection
        #expect(collection.name == "Sample API")
        #expect(collection.auth.kind == .bearer)
        #expect(collection.auth.bearerToken == "{{token}}")
        #expect(collection.variables.map(\.key) == ["baseUrl", "unused"])
        #expect(collection.variables[1].isEnabled == false)
        #expect(collection.items.map(\.name) == ["Users", "Login (form)", "Upload avatar", "Basic", "OAuth thing", "GraphQL", "Shorthand"])

        let users = try #require(collection.items[0].folder)
        #expect(users.description == "User endpoints")
        #expect(users.auth.kind == .inherit)

        let list = try #require(users.items[0].request)
        #expect(list.url == "{{baseUrl}}/users?page=1&limit=20")
        #expect(list.queryParams.map(\.key) == ["page", "limit", "sort"])
        #expect(list.queryParams[2].isEnabled == false)
        #expect(list.headers[1].isEnabled == false)
        #expect(list.auth.kind == .inherit)
        #expect(collection.effectiveAuth(forItem: list.id).bearerToken == "{{token}}")

        let create = try #require(users.items[1].request)
        #expect(create.method == .post)
        #expect(create.body.mode == .raw)
        #expect(create.body.rawLanguage == .json)
        #expect(create.body.raw.contains("\"Ada\""))

        let login = try #require(collection.items[1].request)
        #expect(login.auth.kind == .none)
        #expect(login.body.mode == .urlEncoded)
        #expect(login.body.urlEncoded.map(\.isEnabled) == [true, false])

        let upload = try #require(collection.items[2].request)
        #expect(upload.auth.kind == .apiKey)
        #expect(upload.auth.apiKeyName == "X-API-Key")
        #expect(upload.auth.apiKeyLocation == .header)
        #expect(upload.body.formData.map(\.kind) == [.text, .file])
        #expect(upload.body.formData[1].filePath == "/tmp/avatar.png")

        let basic = try #require(collection.items[3].request)
        #expect(basic.auth.basicUsername == "ada")
        #expect(basic.auth.basicPassword == "pw")

        let oauth = try #require(collection.items[4].request)
        #expect(oauth.auth.kind == .none)

        let graphQL = try #require(collection.items[5].request)
        #expect(JSONFormatter.minify(graphQL.body.raw) == #"{"query":"{ viewer { login } }","variables":{}}"#)

        let shorthand = try #require(collection.items[6].request)
        #expect(shorthand.url == "https://example.com/plain")

        #expect(result.warnings.count == 5)
        #expect(result.warnings.contains { $0.contains("2 个脚本") })
        #expect(result.warnings.contains { $0.contains("1 个示例响应") })
        #expect(result.warnings.contains { $0.contains("oauth2") })
        #expect(result.warnings.contains { $0.contains("路径变量") })
        #expect(result.warnings.contains { $0.contains("GraphQL") })
    }

    @Test func exportThenImportRoundTrips() throws {
        let original = try PostmanImporter.importCollection(from: try fixture()).collection
        let exported = try PostmanExporter.export(original)
        let json = String(decoding: exported, as: UTF8.self)
        #expect(json.contains(PM.schemaV21))
        let reimported = try PostmanImporter.importCollection(from: exported).collection

        // Ids are regenerated on import; compare structure and content.
        func strip(_ items: [CollectionItem]) -> [String] {
            var lines: [String] = []
            RequestCollection.walk(items) { item in
                switch item {
                case .folder(let folder):
                    lines.append("F \(folder.name) \(folder.auth.kind)")
                case .request(let r):
                    let headers = r.headers.map { "\($0.key)=\($0.value)/\($0.isEnabled)" }
                    let params = r.queryParams.map { "\($0.key)=\($0.value)/\($0.isEnabled)" }
                    let form = r.body.formData.map { "\($0.key):\($0.kind):\($0.value):\($0.filePath ?? "")" }
                    let encoded = r.body.urlEncoded.map { "\($0.key)=\($0.value)/\($0.isEnabled)" }
                    lines.append("R \(r.name) \(r.method) \(r.url) \(headers) \(params) \(r.body.mode) \(r.body.raw) \(r.body.rawLanguage) \(form) \(encoded) \(r.auth)")
                }
            }
            return lines
        }
        #expect(strip(reimported.items) == strip(original.items))
        #expect(reimported.variables.map(\.key) == original.variables.map(\.key))
        #expect(reimported.variables.map(\.isEnabled) == original.variables.map(\.isEnabled))
        #expect(reimported.auth == original.auth)
        #expect(reimported.description == original.description)
    }

    @Test func urlObjectSplitsTemplatedURL() {
        let request = HTTPRequest(url: "{{baseUrl}}:8080/v1/users?x=1#frag")
        let object = PostmanExporter.urlObject(for: request)
        #expect(object.host?.parts == ["{{baseUrl}}"])
        #expect(object.port == "8080")
        #expect(object.path?.parts == ["v1", "users"])
        #expect(object.query?.map(\.key) == ["x"])
        #expect(object.hash == "frag")

        let plain = PostmanExporter.urlObject(for: HTTPRequest(url: "https://api.example.com/a"))
        #expect(plain.protocol == "https")
        #expect(plain.host?.parts == ["api", "example", "com"])
    }

    @Test func environmentRoundTrip() throws {
        let environment = APIEnvironment(name: "Dev", variables: [
            KeyValue(key: "host", value: "localhost"),
            KeyValue(key: "off", value: "1", isEnabled: false),
        ])
        let data = try PostmanExporter.export(environment: environment)
        #expect(PostmanImporter.detect(data) == .environment)
        let imported = try PostmanImporter.importEnvironment(from: data)
        #expect(imported.name == "Dev")
        #expect(imported.variables.map(\.key) == ["host", "off"])
        #expect(imported.variables.map(\.isEnabled) == [true, false])
    }

    @Test func rejectsV1() {
        #expect(throws: PostmanImportError.unsupportedV1) {
            try PostmanImporter.importCollection(from: Data(#"{"id":"1","name":"Old","requests":[]}"#.utf8))
        }
    }
}
