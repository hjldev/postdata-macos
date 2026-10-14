import Foundation

public enum PostmanImportError: LocalizedError, Equatable {
    case invalidJSON
    case unsupportedV1
    case unrecognizedFormat

    public var errorDescription: String? {
        switch self {
        case .invalidJSON: "文件不是有效的 JSON"
        case .unsupportedV1: "不支持 Postman v1 格式，请在 Postman 中重新导出为 Collection v2.1"
        case .unrecognizedFormat: "无法识别的文件格式（支持 Postman Collection v2.0/v2.1 和 Environment）"
        }
    }
}

public enum PostmanFileKind: Equatable, Sendable {
    case collection
    case environment
    case unknown
}

public struct CollectionImportResult: Sendable {
    public var collection: RequestCollection
    /// Things that could not be imported, phrased for the user.
    public var warnings: [String]
}

/// Converts Postman Collection v2.0/v2.1 and Environment exports into PostData models.
public enum PostmanImporter {
    public static func detect(_ data: Data) -> PostmanFileKind {
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: data) else { return .unknown }
        if json["info"] != nil, json["item"] != nil { return .collection }
        if case .array = json["values"] { return .environment }
        return .unknown
    }

    public static func importCollection(from data: Data) throws -> CollectionImportResult {
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: data) else { throw PostmanImportError.invalidJSON }
        if json["requests"] != nil, json["info"] == nil { throw PostmanImportError.unsupportedV1 }
        guard json["info"] != nil else { throw PostmanImportError.unrecognizedFormat }
        let dto: PM.Collection
        do {
            dto = try JSONDecoder().decode(PM.Collection.self, from: data)
        } catch {
            throw PostmanImportError.unrecognizedFormat
        }

        var context = Context()
        context.countEvents(dto.event)
        let items = dto.item.compactMap { context.map($0) }
        let variables = (dto.variable ?? []).compactMap { variable -> KeyValue? in
            guard let key = variable.key, !key.isEmpty else { return nil }
            return KeyValue(
                key: key,
                value: variable.value?.stringValue ?? "",
                isEnabled: !(variable.disabled ?? false),
                description: variable.description?.content ?? ""
            )
        }
        var auth = dto.auth.map { context.map($0) } ?? .none
        if auth.kind == .inherit { auth = .none }

        let collection = RequestCollection(
            name: dto.info.name,
            description: dto.info.description?.content ?? "",
            items: items,
            variables: variables,
            auth: auth
        )
        return CollectionImportResult(collection: collection, warnings: context.warnings)
    }

    public static func importEnvironment(from data: Data) throws -> APIEnvironment {
        guard let dto = try? JSONDecoder().decode(PM.Environment.self, from: data) else {
            throw PostmanImportError.unrecognizedFormat
        }
        let variables = dto.values.map {
            KeyValue(key: $0.key, value: $0.value?.stringValue ?? "", isEnabled: $0.enabled ?? true)
        }
        return APIEnvironment(name: dto.name ?? "Imported Environment", variables: variables)
    }

    // MARK: Mapping

    private struct Context {
        var scriptCount = 0
        var exampleCount = 0
        var pathVariableRequests = 0
        var graphQLRequests = 0
        var unsupportedAuth = Set<String>()

        var warnings: [String] {
            var result: [String] = []
            if scriptCount > 0 { result.append("\(scriptCount) 个脚本（Pre-request / Tests）未导入，PostData 暂不支持脚本") }
            if exampleCount > 0 { result.append("\(exampleCount) 个示例响应（Examples）未导入") }
            if pathVariableRequests > 0 { result.append("\(pathVariableRequests) 个请求使用了路径变量（如 :id），暂不支持，请改用 {{变量}}") }
            if graphQLRequests > 0 { result.append("\(graphQLRequests) 个 GraphQL 请求已转换为 raw JSON body") }
            if !unsupportedAuth.isEmpty {
                result.append("不支持的认证类型：\(unsupportedAuth.sorted().joined(separator: ", "))，已设为 No Auth")
            }
            return result
        }

        mutating func countEvents(_ events: [JSONValue]?) {
            for event in events ?? [] {
                if case .array(let lines) = event["script"]?["exec"] ?? .null {
                    if lines.contains(where: { !($0.stringValue ?? "").trimmingCharacters(in: .whitespaces).isEmpty }) {
                        scriptCount += 1
                    }
                } else if let line = event["script"]?["exec"]?.stringValue, !line.trimmingCharacters(in: .whitespaces).isEmpty {
                    scriptCount += 1
                }
            }
        }

        mutating func map(_ item: PM.Item) -> CollectionItem? {
            countEvents(item.event)
            exampleCount += item.response?.count ?? 0
            if let children = item.item {
                return .folder(Folder(
                    name: item.name ?? "Folder",
                    description: item.description?.content ?? "",
                    items: children.compactMap { map($0) },
                    auth: item.auth.map { map($0) } ?? .inherit
                ))
            }
            guard let request = item.request else { return nil }
            return .request(map(request, name: item.name, description: item.description?.content))
        }

        mutating func map(_ dto: PM.Request, name: String?, description: String?) -> HTTPRequest {
            var url = ""
            var params: [KeyValue]?
            switch dto.url {
            case .raw(let text):
                url = text
            case .object(let object):
                url = object.raw ?? Self.buildRaw(object)
                if let query = object.query {
                    let mapped = query.map {
                        KeyValue(
                            key: $0.key ?? "",
                            value: $0.value ?? "",
                            isEnabled: !($0.disabled ?? false),
                            description: $0.description?.content ?? ""
                        )
                    }
                    params = mapped
                    if URLQuerySync.split(url).query == nil, mapped.contains(where: \.isEnabled) {
                        url = URLQuerySync.url(url, replacingQueryWith: mapped)
                    }
                }
                if !(object.variable ?? []).isEmpty { pathVariableRequests += 1 }
            case nil:
                break
            }

            let headers = (dto.header ?? []).map {
                KeyValue(key: $0.key, value: $0.value ?? "", isEnabled: !($0.disabled ?? false), description: $0.description?.content ?? "")
            }

            return HTTPRequest(
                name: name ?? HTTPRequest.suggestedName(for: url),
                method: HTTPMethod(dto.method ?? "GET"),
                url: url,
                queryParams: params,
                headers: headers,
                body: map(dto.body, headers: headers),
                auth: dto.auth.map { map($0) } ?? .inherit,
                description: dto.description?.content ?? description ?? ""
            )
        }

        mutating func map(_ dto: PM.Body?, headers: [KeyValue]) -> RequestBody {
            guard let dto, dto.disabled != true else { return RequestBody() }
            var body = RequestBody()
            switch dto.mode {
            case "raw":
                body.mode = .raw
                body.raw = dto.raw ?? ""
                if let language = dto.options?["raw"]?["language"]?.stringValue,
                   let mapped = RequestBody.RawLanguage(rawValue: language) {
                    body.rawLanguage = mapped
                } else if let contentType = headers.active.first(where: { $0.key.lowercased() == "content-type" })?.value,
                          let mapped = RequestBody.RawLanguage(contentType: contentType) {
                    body.rawLanguage = mapped
                } else {
                    body.rawLanguage = JSONFormatter.isValid(body.raw) ? .json : .text
                }
            case "urlencoded":
                body.mode = .urlEncoded
                body.urlEncoded = (dto.urlencoded ?? []).map {
                    KeyValue(key: $0.key, value: $0.value ?? "", isEnabled: !($0.disabled ?? false), description: $0.description?.content ?? "")
                }
            case "formdata":
                body.mode = .formData
                body.formData = (dto.formdata ?? []).map { param in
                    let isFile = param.type == "file"
                    var path: String?
                    if isFile {
                        switch param.src {
                        case .string(let src): path = src
                        case .array(let list): path = list.first?.stringValue
                        default: path = nil
                        }
                    }
                    return FormDataField(
                        key: param.key,
                        kind: isFile ? .file : .text,
                        value: isFile ? "" : (param.value ?? ""),
                        filePath: path,
                        contentType: param.contentType,
                        isEnabled: !(param.disabled ?? false),
                        description: param.description?.content ?? ""
                    )
                }
            case "file":
                body.mode = .binary
                body.binaryFilePath = dto.file?.src
            case "graphql":
                graphQLRequests += 1
                body.mode = .raw
                body.rawLanguage = .json
                let query = dto.graphql?["query"]?.stringValue ?? ""
                var variables = dto.graphql?["variables"]?.stringValue ?? ""
                if variables.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !JSONFormatter.isValid(variables) {
                    variables = "{}"
                }
                let json = "{\"query\":\(Escaping.doubleQuoted(query)),\"variables\":\(variables)}"
                body.raw = JSONFormatter.prettyPrint(json) ?? json
            default:
                break
            }
            return body
        }

        mutating func map(_ dto: PM.AuthDTO) -> Auth {
            switch dto.type {
            case "noauth":
                return .none
            case "inherit":
                return .inherit
            case "bearer":
                return .bearer(dto.bearer?["token"] ?? "")
            case "basic":
                return .basic(username: dto.basic?["username"] ?? "", password: dto.basic?["password"] ?? "")
            case "apikey":
                let location: APIKeyLocation = dto.apikey?["in"] == "query" ? .query : .header
                return .apiKey(name: dto.apikey?["key"] ?? "", value: dto.apikey?["value"] ?? "", location: location)
            default:
                unsupportedAuth.insert(dto.type)
                return .none
            }
        }

        static func buildRaw(_ object: PM.URLObject) -> String {
            var raw = ""
            if let scheme = object.protocol, !scheme.isEmpty { raw += scheme + "://" }
            raw += (object.host?.parts ?? []).joined(separator: ".")
            if let port = object.port, !port.isEmpty { raw += ":" + port }
            let path = object.path?.parts ?? []
            if !path.isEmpty { raw += "/" + path.joined(separator: "/") }
            if let hash = object.hash, !hash.isEmpty { raw += "#" + hash }
            return raw
        }
    }
}
