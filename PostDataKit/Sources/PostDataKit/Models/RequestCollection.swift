import Foundation

/// A folder inside a collection.
public struct Folder: Identifiable, Hashable, Sendable, Codable {
    public var id: UUID
    public var name: String
    public var description: String
    public var items: [CollectionItem]
    public var auth: Auth

    public init(id: UUID = UUID(), name: String, description: String = "", items: [CollectionItem] = [], auth: Auth = .inherit) {
        self.id = id
        self.name = name
        self.description = description
        self.items = items
        self.auth = auth
    }

    private enum CodingKeys: String, CodingKey { case id, name, description, items, auth }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Folder"
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        items = try c.decodeIfPresent([CollectionItem].self, forKey: .items) ?? []
        auth = try c.decodeIfPresent(Auth.self, forKey: .auth) ?? .inherit
    }
}

/// A node in a collection tree.
public enum CollectionItem: Identifiable, Hashable, Sendable, Codable {
    case folder(Folder)
    case request(HTTPRequest)

    public var id: UUID {
        switch self {
        case .folder(let folder): folder.id
        case .request(let request): request.id
        }
    }

    public var name: String {
        get {
            switch self {
            case .folder(let folder): folder.name
            case .request(let request): request.name
            }
        }
        set {
            switch self {
            case .folder(var folder):
                folder.name = newValue
                self = .folder(folder)
            case .request(var request):
                request.name = newValue
                self = .request(request)
            }
        }
    }

    public var folder: Folder? {
        if case .folder(let folder) = self { return folder }
        return nil
    }

    public var request: HTTPRequest? {
        if case .request(let request) = self { return request }
        return nil
    }

    public var isFolder: Bool { folder != nil }

    private enum CodingKeys: String, CodingKey { case type, folder, request }
    private enum ItemType: String, Codable { case folder, request }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(ItemType.self, forKey: .type) {
        case .folder: self = .folder(try c.decode(Folder.self, forKey: .folder))
        case .request: self = .request(try c.decode(HTTPRequest.self, forKey: .request))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .folder(let folder):
            try c.encode(ItemType.folder, forKey: .type)
            try c.encode(folder, forKey: .folder)
        case .request(let request):
            try c.encode(ItemType.request, forKey: .type)
            try c.encode(request, forKey: .request)
        }
    }
}

/// A named tree of folders and requests, with its own variables and default auth.
public struct RequestCollection: Identifiable, Hashable, Sendable, Codable {
    public var id: UUID
    public var name: String
    public var description: String
    public var items: [CollectionItem]
    public var variables: [KeyValue]
    /// Collection-level auth. `.inherit` is treated as `.none`.
    public var auth: Auth

    public init(
        id: UUID = UUID(),
        name: String,
        description: String = "",
        items: [CollectionItem] = [],
        variables: [KeyValue] = [],
        auth: Auth = .none
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.items = items
        self.variables = variables
        self.auth = auth
    }

    private enum CodingKeys: String, CodingKey { case id, name, description, items, variables, auth }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Collection"
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        items = try c.decodeIfPresent([CollectionItem].self, forKey: .items) ?? []
        variables = try c.decodeIfPresent([KeyValue].self, forKey: .variables) ?? []
        auth = try c.decodeIfPresent(Auth.self, forKey: .auth) ?? .none
    }
}
