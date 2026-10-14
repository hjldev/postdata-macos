import Foundation

/// Any JSON value, for fields whose type varies between Postman exports.
public enum JSONValue: Hashable, Sendable, Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    /// A string rendering of scalar values.
    public var stringValue: String? {
        switch self {
        case .string(let v): v
        case .number(let v): v == v.rounded() && abs(v) < 1e15 ? String(Int64(v)) : String(v)
        case .bool(let v): v ? "true" : "false"
        case .null: nil
        case .array, .object: nil
        }
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let dict) = self { return dict[key] }
        return nil
    }
}

/// Wire format of Postman Collection v2.0 / v2.1 (only the parts PostData maps).
enum PM {
    static let schemaV21 = "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"

    struct Collection: Codable {
        var info: Info
        var item: [Item]
        var variable: [Variable]?
        var auth: AuthDTO?
        var event: [JSONValue]?
    }

    struct Info: Codable {
        var _postman_id: String?
        var name: String
        var description: Description?
        var schema: String?
    }

    /// `description` is either a string or `{ "content": "…" }`.
    struct Description: Codable {
        var content: String

        init(_ content: String) { self.content = content }

        init(from decoder: any Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let text = try? c.decode(String.self) {
                content = text
            } else {
                content = (try c.decode(JSONValue.self))["content"]?.stringValue ?? ""
            }
        }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.singleValueContainer()
            try c.encode(content)
        }
    }

    struct Item: Codable {
        var id: String?
        var name: String?
        var description: Description?
        var item: [Item]?
        var request: Request?
        var auth: AuthDTO?
        var event: [JSONValue]?
        var response: [JSONValue]?
    }

    struct Request: Codable {
        var method: String?
        var header: [Header]?
        var url: URLValue?
        var body: Body?
        var auth: AuthDTO?
        var description: Description?

        init(method: String?, header: [Header]?, url: URLValue?, body: Body?, auth: AuthDTO?, description: Description?) {
            self.method = method
            self.header = header
            self.url = url
            self.body = body
            self.auth = auth
            self.description = description
        }

        private enum CodingKeys: String, CodingKey { case method, header, url, body, auth, description }

        /// A request may also be just a URL string.
        init(from decoder: any Decoder) throws {
            if let text = try? decoder.singleValueContainer().decode(String.self) {
                self.init(method: "GET", header: nil, url: .raw(text), body: nil, auth: nil, description: nil)
                return
            }
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                method: try c.decodeIfPresent(String.self, forKey: .method),
                header: (try? c.decodeIfPresent([Header].self, forKey: .header)) ?? nil,
                url: try c.decodeIfPresent(URLValue.self, forKey: .url),
                body: (try? c.decodeIfPresent(Body.self, forKey: .body)) ?? nil,
                auth: (try? c.decodeIfPresent(AuthDTO.self, forKey: .auth)) ?? nil,
                description: (try? c.decodeIfPresent(Description.self, forKey: .description)) ?? nil
            )
        }
    }

    struct Header: Codable {
        var key: String
        var value: String?
        var disabled: Bool?
        var description: Description?
    }

    enum URLValue: Codable {
        case raw(String)
        case object(URLObject)

        init(from decoder: any Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let text = try? c.decode(String.self) {
                self = .raw(text)
            } else {
                self = .object(try c.decode(URLObject.self))
            }
        }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self {
            case .raw(let text): try c.encode(text)
            case .object(let object): try c.encode(object)
            }
        }
    }

    /// `host` and `path` are either a string or an array of segments.
    struct Segments: Codable {
        var parts: [String]

        init(_ parts: [String]) { self.parts = parts }

        init(from decoder: any Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let text = try? c.decode(String.self) {
                parts = [text]
            } else {
                parts = try c.decode([JSONValue].self).compactMap { $0.stringValue ?? $0["value"]?.stringValue }
            }
        }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.singleValueContainer()
            try c.encode(parts)
        }
    }

    struct URLObject: Codable {
        var raw: String?
        var `protocol`: String?
        var host: Segments?
        var port: String?
        var path: Segments?
        var query: [QueryParam]?
        var hash: String?
        var variable: [Variable]?
    }

    struct QueryParam: Codable {
        var key: String?
        var value: String?
        var disabled: Bool?
        var description: Description?
    }

    struct Body: Codable {
        var mode: String?
        var raw: String?
        var urlencoded: [URLEncodedParam]?
        var formdata: [FormParam]?
        var file: File?
        var graphql: JSONValue?
        var options: JSONValue?
        var disabled: Bool?
    }

    struct URLEncodedParam: Codable {
        var key: String
        var value: String?
        var disabled: Bool?
        var description: Description?
    }

    struct FormParam: Codable {
        var key: String
        var value: String?
        var src: JSONValue?
        var type: String?
        var contentType: String?
        var disabled: Bool?
        var description: Description?
    }

    struct File: Codable {
        var src: String?
        var content: String?
    }

    struct AuthAttribute: Codable {
        var key: String
        var value: JSONValue?
        var type: String?
    }

    /// v2.1 stores auth parameters as `[{key, value}]`; v2.0 as a plain object.
    struct AuthAttributes: Codable {
        var items: [AuthAttribute]

        init(_ items: [AuthAttribute]) { self.items = items }

        init(from decoder: any Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let list = try? c.decode([AuthAttribute].self) {
                items = list
            } else {
                let dict = try c.decode([String: JSONValue].self)
                items = dict.map { AuthAttribute(key: $0.key, value: $0.value, type: nil) }
            }
        }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.singleValueContainer()
            try c.encode(items)
        }

        subscript(key: String) -> String {
            items.first { $0.key == key }?.value?.stringValue ?? ""
        }
    }

    struct AuthDTO: Codable {
        var type: String
        var bearer: AuthAttributes?
        var basic: AuthAttributes?
        var apikey: AuthAttributes?
    }

    struct Variable: Codable {
        var id: String?
        var key: String?
        var value: JSONValue?
        var type: String?
        var disabled: Bool?
        var description: Description?
    }

    /// Postman environment / globals export.
    struct Environment: Codable {
        var id: String?
        var name: String?
        var values: [EnvironmentValue]
        var _postman_variable_scope: String?
    }

    struct EnvironmentValue: Codable {
        var key: String
        var value: JSONValue?
        var type: String?
        var enabled: Bool?
    }
}
