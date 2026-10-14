import Foundation

/// A row in a key/value table: query params, headers, url-encoded fields and variables.
public struct KeyValue: Identifiable, Hashable, Sendable, Codable {
    public var id: UUID
    public var key: String
    public var value: String
    public var isEnabled: Bool
    public var description: String

    public init(id: UUID = UUID(), key: String = "", value: String = "", isEnabled: Bool = true, description: String = "") {
        self.id = id
        self.key = key
        self.value = value
        self.isEnabled = isEnabled
        self.description = description
    }

    /// True for a row the user has not typed anything into.
    public var isBlank: Bool { key.isEmpty && value.isEmpty && description.isEmpty }

    private enum CodingKeys: String, CodingKey { case id, key, value, isEnabled, description }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        key = try c.decodeIfPresent(String.self, forKey: .key) ?? ""
        value = try c.decodeIfPresent(String.self, forKey: .value) ?? ""
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
    }
}

extension Array where Element == KeyValue {
    /// Enabled rows that have a key.
    public var active: [KeyValue] { filter { $0.isEnabled && !$0.key.isEmpty } }

    /// Enabled variables as a dictionary; later rows win on duplicate keys.
    public var variableDictionary: [String: String] {
        var result: [String: String] = [:]
        for item in active { result[item.key] = item.value }
        return result
    }
}

/// Postman-style bulk edit format: one `key:value` per line, disabled rows prefixed with `//`.
public enum KeyValueBulkFormat {
    public static func serialize(_ items: [KeyValue]) -> String {
        items.filter { !$0.isBlank }
            .map { ($0.isEnabled ? "" : "//") + $0.key + ":" + $0.value }
            .joined(separator: "\n")
    }

    /// Parses bulk text, reusing ids and descriptions of `existing` rows with the same key.
    public static func parse(_ text: String, existing: [KeyValue] = []) -> [KeyValue] {
        var pool = existing
        var result: [KeyValue] = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            var line = String(rawLine)
            if line.hasSuffix("\r") { line.removeLast() }
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            var isEnabled = true
            if line.hasPrefix("//") {
                isEnabled = false
                line.removeFirst(2)
            }
            let key: String
            let value: String
            if let colon = line.firstIndex(of: ":") {
                key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            } else {
                key = line.trimmingCharacters(in: .whitespaces)
                value = ""
            }
            if let index = pool.firstIndex(where: { $0.key == key }) {
                let reused = pool.remove(at: index)
                result.append(KeyValue(id: reused.id, key: key, value: value, isEnabled: isEnabled, description: reused.description))
            } else {
                result.append(KeyValue(key: key, value: value, isEnabled: isEnabled))
            }
        }
        return result
    }
}
