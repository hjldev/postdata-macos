import Foundation

/// A named set of variables. Globals are stored as an `APIEnvironment` too.
public struct APIEnvironment: Identifiable, Hashable, Sendable, Codable {
    public var id: UUID
    public var name: String
    public var variables: [KeyValue]

    public init(id: UUID = UUID(), name: String, variables: [KeyValue] = []) {
        self.id = id
        self.name = name
        self.variables = variables
    }

    private enum CodingKeys: String, CodingKey { case id, name, variables }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Environment"
        variables = try c.decodeIfPresent([KeyValue].self, forKey: .variables) ?? []
    }
}

/// One sent request, kept in history.
public struct HistoryEntry: Identifiable, Hashable, Sendable, Codable {
    public var id: UUID
    public var date: Date
    public var request: HTTPRequest
    public var statusCode: Int?
    public var duration: TimeInterval?
    public var size: Int?
    public var errorMessage: String?

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        request: HTTPRequest,
        statusCode: Int? = nil,
        duration: TimeInterval? = nil,
        size: Int? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.date = date
        self.request = request
        self.statusCode = statusCode
        self.duration = duration
        self.size = size
        self.errorMessage = errorMessage
    }
}
