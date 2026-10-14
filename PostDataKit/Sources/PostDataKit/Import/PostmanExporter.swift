import Foundation

/// Writes PostData models as Postman Collection v2.1 / Environment JSON.
public enum PostmanExporter {
    public enum VariableScope: String, Sendable {
        case environment, globals
    }

    public static func export(_ collection: RequestCollection) throws -> Data {
        let dto = PM.Collection(
            info: PM.Info(
                _postman_id: collection.id.uuidString.lowercased(),
                name: collection.name,
                description: collection.description.isEmpty ? nil : PM.Description(collection.description),
                schema: PM.schemaV21
            ),
            item: collection.items.map(map),
            variable: collection.variables.isEmpty ? nil : collection.variables.filter { !$0.isBlank }.map {
                PM.Variable(id: nil, key: $0.key, value: .string($0.value), type: "string", disabled: $0.isEnabled ? nil : true, description: nil)
            },
            auth: map(collection.auth),
            event: nil
        )
        return try encoder.encode(dto)
    }

    public static func export(environment: APIEnvironment, scope: VariableScope = .environment) throws -> Data {
        let dto = PM.Environment(
            id: environment.id.uuidString.lowercased(),
            name: environment.name,
            values: environment.variables.filter { !$0.isBlank }.map {
                PM.EnvironmentValue(key: $0.key, value: .string($0.value), type: "default", enabled: $0.isEnabled)
            },
            _postman_variable_scope: scope.rawValue
        )
        return try encoder.encode(dto)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    // MARK: Mapping

    private static func map(_ item: CollectionItem) -> PM.Item {
        switch item {
        case .folder(let folder):
            return PM.Item(
                id: folder.id.uuidString.lowercased(),
                name: folder.name,
                description: folder.description.isEmpty ? nil : PM.Description(folder.description),
                item: folder.items.map(map),
                request: nil,
                auth: map(folder.auth),
                event: nil,
                response: nil
            )
        case .request(let request):
            return PM.Item(
                id: request.id.uuidString.lowercased(),
                name: request.name,
                description: nil,
                item: nil,
                request: PM.Request(
                    method: request.method.rawValue,
                    header: request.headers.filter { !$0.isBlank }.map {
                        PM.Header(
                            key: $0.key,
                            value: $0.value,
                            disabled: $0.isEnabled ? nil : true,
                            description: $0.description.isEmpty ? nil : PM.Description($0.description)
                        )
                    },
                    url: .object(urlObject(for: request)),
                    body: body(for: request.body),
                    auth: map(request.auth),
                    description: request.description.isEmpty ? nil : PM.Description(request.description)
                ),
                auth: nil,
                event: nil,
                response: []
            )
        }
    }

    /// `.inherit` is expressed in Postman by omitting `auth`.
    private static func map(_ auth: Auth) -> PM.AuthDTO? {
        func attr(_ key: String, _ value: String) -> PM.AuthAttribute {
            PM.AuthAttribute(key: key, value: .string(value), type: "string")
        }
        switch auth.kind {
        case .inherit:
            return nil
        case .none:
            return PM.AuthDTO(type: "noauth")
        case .bearer:
            return PM.AuthDTO(type: "bearer", bearer: PM.AuthAttributes([attr("token", auth.bearerToken)]))
        case .basic:
            return PM.AuthDTO(type: "basic", basic: PM.AuthAttributes([
                attr("username", auth.basicUsername),
                attr("password", auth.basicPassword),
            ]))
        case .apiKey:
            return PM.AuthDTO(type: "apikey", apikey: PM.AuthAttributes([
                attr("key", auth.apiKeyName),
                attr("value", auth.apiKeyValue),
                attr("in", auth.apiKeyLocation.rawValue),
            ]))
        }
    }

    private static func body(for body: RequestBody) -> PM.Body? {
        switch body.mode {
        case .none:
            return nil
        case .raw:
            return PM.Body(
                mode: "raw",
                raw: body.raw,
                options: .object(["raw": .object(["language": .string(body.rawLanguage.rawValue)])])
            )
        case .urlEncoded:
            return PM.Body(mode: "urlencoded", urlencoded: body.urlEncoded.filter { !$0.isBlank }.map {
                PM.URLEncodedParam(
                    key: $0.key,
                    value: $0.value,
                    disabled: $0.isEnabled ? nil : true,
                    description: $0.description.isEmpty ? nil : PM.Description($0.description)
                )
            })
        case .formData:
            return PM.Body(mode: "formdata", formdata: body.formData.filter { !$0.isBlank }.map { field in
                PM.FormParam(
                    key: field.key,
                    value: field.kind == .text ? field.value : nil,
                    src: field.kind == .file ? field.filePath.map(JSONValue.string) : nil,
                    type: field.kind.rawValue,
                    contentType: field.contentType,
                    disabled: field.isEnabled ? nil : true,
                    description: field.description.isEmpty ? nil : PM.Description(field.description)
                )
            })
        case .binary:
            return PM.Body(mode: "file", file: PM.File(src: body.binaryFilePath))
        }
    }

    /// Splits a raw URL into Postman's structured form; variables like `{{baseUrl}}` stay intact.
    static func urlObject(for request: HTTPRequest) -> PM.URLObject {
        let (base, _, fragment) = URLQuerySync.split(request.url)
        var rest = Substring(base)
        var scheme: String?
        if let range = rest.range(of: "://") {
            scheme = String(rest[..<range.lowerBound])
            rest = rest[range.upperBound...]
        }
        let authority: Substring
        let pathPart: Substring
        if let slash = rest.firstIndex(of: "/") {
            authority = rest[..<slash]
            pathPart = rest[rest.index(after: slash)...]
        } else {
            authority = rest
            pathPart = ""
        }
        var host = String(authority)
        var port: String?
        if let colon = authority.lastIndex(of: ":"), !authority[authority.index(after: colon)...].contains("}") {
            host = String(authority[..<colon])
            port = String(authority[authority.index(after: colon)...])
        }
        let query = request.queryParams.filter { !$0.isBlank }.map {
            PM.QueryParam(
                key: $0.key,
                value: $0.value,
                disabled: $0.isEnabled ? nil : true,
                description: $0.description.isEmpty ? nil : PM.Description($0.description)
            )
        }
        return PM.URLObject(
            raw: request.url,
            protocol: scheme,
            host: host.isEmpty ? nil : PM.Segments(host.split(separator: ".", omittingEmptySubsequences: false).map(String.init)),
            port: port,
            path: pathPart.isEmpty ? nil : PM.Segments(pathPart.split(separator: "/", omittingEmptySubsequences: false).map(String.init)),
            query: query.isEmpty ? nil : query,
            hash: fragment,
            variable: nil
        )
    }
}
