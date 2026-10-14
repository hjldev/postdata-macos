import Foundation

/// An HTTP method. Backed by a string so custom methods (e.g. `PROPFIND`) round-trip unchanged.
public struct HTTPMethod: RawRepresentable, Hashable, Sendable, Codable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue.trimmingCharacters(in: .whitespaces).uppercased()
    }

    public init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    public init(from decoder: any Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }

    public static let get: HTTPMethod = "GET"
    public static let post: HTTPMethod = "POST"
    public static let put: HTTPMethod = "PUT"
    public static let patch: HTTPMethod = "PATCH"
    public static let delete: HTTPMethod = "DELETE"
    public static let head: HTTPMethod = "HEAD"
    public static let options: HTTPMethod = "OPTIONS"

    public static let standard: [HTTPMethod] = [.get, .post, .put, .patch, .delete, .head, .options]

    /// URLSession refuses to send a body with these methods.
    public var allowsBody: Bool { self != .get && self != .head }
}
