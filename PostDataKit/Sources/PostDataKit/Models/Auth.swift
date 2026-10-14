import Foundation

public enum APIKeyLocation: String, Hashable, Sendable, Codable, CaseIterable {
    case header, query
}

/// Authorization settings. Fields for every kind are kept so switching kinds never loses input.
public struct Auth: Hashable, Sendable, Codable {
    public enum Kind: String, Hashable, Sendable, Codable, CaseIterable {
        case inherit, none, bearer, basic, apiKey

        public var title: String {
            switch self {
            case .inherit: "Inherit auth from parent"
            case .none: "No Auth"
            case .bearer: "Bearer Token"
            case .basic: "Basic Auth"
            case .apiKey: "API Key"
            }
        }
    }

    public var kind: Kind
    public var bearerToken: String
    public var basicUsername: String
    public var basicPassword: String
    public var apiKeyName: String
    public var apiKeyValue: String
    public var apiKeyLocation: APIKeyLocation

    public init(
        kind: Kind,
        bearerToken: String = "",
        basicUsername: String = "",
        basicPassword: String = "",
        apiKeyName: String = "",
        apiKeyValue: String = "",
        apiKeyLocation: APIKeyLocation = .header
    ) {
        self.kind = kind
        self.bearerToken = bearerToken
        self.basicUsername = basicUsername
        self.basicPassword = basicPassword
        self.apiKeyName = apiKeyName
        self.apiKeyValue = apiKeyValue
        self.apiKeyLocation = apiKeyLocation
    }

    public static let inherit = Auth(kind: .inherit)
    public static let none = Auth(kind: .none)

    public static func bearer(_ token: String) -> Auth {
        Auth(kind: .bearer, bearerToken: token)
    }

    public static func basic(username: String, password: String) -> Auth {
        Auth(kind: .basic, basicUsername: username, basicPassword: password)
    }

    public static func apiKey(name: String, value: String, location: APIKeyLocation = .header) -> Auth {
        Auth(kind: .apiKey, apiKeyName: name, apiKeyValue: value, apiKeyLocation: location)
    }

    private enum CodingKeys: String, CodingKey {
        case kind, bearerToken, basicUsername, basicPassword, apiKeyName, apiKeyValue, apiKeyLocation
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .none
        bearerToken = try c.decodeIfPresent(String.self, forKey: .bearerToken) ?? ""
        basicUsername = try c.decodeIfPresent(String.self, forKey: .basicUsername) ?? ""
        basicPassword = try c.decodeIfPresent(String.self, forKey: .basicPassword) ?? ""
        apiKeyName = try c.decodeIfPresent(String.self, forKey: .apiKeyName) ?? ""
        apiKeyValue = try c.decodeIfPresent(String.self, forKey: .apiKeyValue) ?? ""
        apiKeyLocation = try c.decodeIfPresent(APIKeyLocation.self, forKey: .apiKeyLocation) ?? .header
    }
}
