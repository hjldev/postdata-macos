import Foundation

/// A request body. Data for every mode is kept so switching modes never loses what the user typed.
public struct RequestBody: Hashable, Sendable, Codable {
    public enum Mode: String, Hashable, Sendable, Codable, CaseIterable {
        case none, formData, urlEncoded, raw, binary

        public var title: String {
            switch self {
            case .none: "none"
            case .formData: "form-data"
            case .urlEncoded: "x-www-form-urlencoded"
            case .raw: "raw"
            case .binary: "binary"
            }
        }
    }

    public enum RawLanguage: String, Hashable, Sendable, Codable, CaseIterable {
        case json, text, xml, html, javascript

        public var title: String {
            switch self {
            case .json: "JSON"
            case .text: "Text"
            case .xml: "XML"
            case .html: "HTML"
            case .javascript: "JavaScript"
            }
        }

        public var contentType: String {
            switch self {
            case .json: "application/json"
            case .text: "text/plain"
            case .xml: "application/xml"
            case .html: "text/html"
            case .javascript: "application/javascript"
            }
        }

        /// Best guess from a Content-Type header value.
        public init?(contentType: String) {
            let type = contentType.lowercased()
            if type.contains("json") { self = .json }
            else if type.contains("xml") { self = .xml }
            else if type.contains("html") { self = .html }
            else if type.contains("javascript") { self = .javascript }
            else if type.hasPrefix("text/") { self = .text }
            else { return nil }
        }
    }

    public var mode: Mode
    public var raw: String
    public var rawLanguage: RawLanguage
    public var urlEncoded: [KeyValue]
    public var formData: [FormDataField]
    public var binaryFilePath: String?

    public init(
        mode: Mode = .none,
        raw: String = "",
        rawLanguage: RawLanguage = .json,
        urlEncoded: [KeyValue] = [],
        formData: [FormDataField] = [],
        binaryFilePath: String? = nil
    ) {
        self.mode = mode
        self.raw = raw
        self.rawLanguage = rawLanguage
        self.urlEncoded = urlEncoded
        self.formData = formData
        self.binaryFilePath = binaryFilePath
    }

    public static func json(_ text: String) -> RequestBody {
        RequestBody(mode: .raw, raw: text, rawLanguage: .json)
    }

    private enum CodingKeys: String, CodingKey { case mode, raw, rawLanguage, urlEncoded, formData, binaryFilePath }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = try c.decodeIfPresent(Mode.self, forKey: .mode) ?? .none
        raw = try c.decodeIfPresent(String.self, forKey: .raw) ?? ""
        rawLanguage = try c.decodeIfPresent(RawLanguage.self, forKey: .rawLanguage) ?? .json
        urlEncoded = try c.decodeIfPresent([KeyValue].self, forKey: .urlEncoded) ?? []
        formData = try c.decodeIfPresent([FormDataField].self, forKey: .formData) ?? []
        binaryFilePath = try c.decodeIfPresent(String.self, forKey: .binaryFilePath)
    }
}

/// A multipart/form-data field: either text or a file on disk.
public struct FormDataField: Identifiable, Hashable, Sendable, Codable {
    public enum Kind: String, Hashable, Sendable, Codable, CaseIterable {
        case text, file
    }

    public var id: UUID
    public var key: String
    public var kind: Kind
    public var value: String
    public var filePath: String?
    /// Explicit part Content-Type; inferred from the file extension when nil.
    public var contentType: String?
    public var isEnabled: Bool
    public var description: String

    public init(
        id: UUID = UUID(),
        key: String = "",
        kind: Kind = .text,
        value: String = "",
        filePath: String? = nil,
        contentType: String? = nil,
        isEnabled: Bool = true,
        description: String = ""
    ) {
        self.id = id
        self.key = key
        self.kind = kind
        self.value = value
        self.filePath = filePath
        self.contentType = contentType
        self.isEnabled = isEnabled
        self.description = description
    }

    public var isBlank: Bool { key.isEmpty && value.isEmpty && filePath == nil && description.isEmpty }

    private enum CodingKeys: String, CodingKey { case id, key, kind, value, filePath, contentType, isEnabled, description }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        key = try c.decodeIfPresent(String.self, forKey: .key) ?? ""
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .text
        value = try c.decodeIfPresent(String.self, forKey: .value) ?? ""
        filePath = try c.decodeIfPresent(String.self, forKey: .filePath)
        contentType = try c.decodeIfPresent(String.self, forKey: .contentType)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
    }
}
