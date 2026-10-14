import Foundation

/// Replaces `{{name}}` placeholders with variable values.
///
/// Scopes are layered from least to most specific (globals, collection, environment);
/// a more specific scope wins. Values may reference other variables; expansion stops
/// at `maxDepth` so cycles leave the placeholder in place instead of looping.
public struct VariableResolver: Sendable {
    public struct Result: Hashable, Sendable {
        public var text: String
        /// Names that had no value in any scope (dynamic variables are never listed).
        public var unresolved: [String]
    }

    /// Lowest priority first.
    public var scopes: [[String: String]]
    public var maxDepth = 10

    public init(scopes: [[String: String]] = []) {
        self.scopes = scopes
    }

    public init(globals: [KeyValue] = [], collection: [KeyValue] = [], environment: [KeyValue] = []) {
        self.scopes = [globals.variableDictionary, collection.variableDictionary, environment.variableDictionary]
    }

    public static let empty = VariableResolver()

    public func value(for name: String) -> String? {
        for scope in scopes.reversed() {
            if let value = scope[name] { return value }
        }
        return nil
    }

    public func resolve(_ text: String) -> String {
        resolveDetailed(text).text
    }

    public func resolveDetailed(_ text: String) -> Result {
        var unresolved: [String] = []
        let output = expand(text, depth: 0, unresolved: &unresolved)
        var seen = Set<String>()
        return Result(text: output, unresolved: unresolved.filter { seen.insert($0).inserted })
    }

    /// The variable names referenced in a text, in order of first appearance.
    public static func referencedNames(in text: String) -> [String] {
        var seen = Set<String>()
        return placeholders(in: text).map(\.name).filter { seen.insert($0).inserted }
    }

    // MARK: Private

    private func expand(_ text: String, depth: Int, unresolved: inout [String]) -> String {
        guard text.contains("{{") else { return text }
        var output = ""
        var cursor = text.startIndex
        for placeholder in Self.placeholders(in: text) {
            output += text[cursor..<placeholder.range.lowerBound]
            cursor = placeholder.range.upperBound
            let name = placeholder.name
            if name.hasPrefix("$"), let dynamic = DynamicVariables.value(for: name) {
                output += dynamic
            } else if let value = value(for: name) {
                if depth < maxDepth {
                    output += expand(value, depth: depth + 1, unresolved: &unresolved)
                } else {
                    output += value
                }
            } else {
                unresolved.append(name)
                output += text[placeholder.range]
            }
        }
        output += text[cursor...]
        return output
    }

    struct Placeholder {
        var name: String
        var range: Range<String.Index>
    }

    static func placeholders(in text: String) -> [Placeholder] {
        var result: [Placeholder] = []
        var searchStart = text.startIndex
        while let open = text.range(of: "{{", range: searchStart..<text.endIndex) {
            guard let close = text.range(of: "}}", range: open.upperBound..<text.endIndex) else { break }
            let inner = text[open.upperBound..<close.lowerBound]
            // `{{a{{b}}` — restart from the innermost opening braces.
            if let nested = inner.range(of: "{{", options: .backwards) {
                searchStart = nested.lowerBound
                continue
            }
            let name = inner.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty, !name.contains("\n") {
                result.append(Placeholder(name: name, range: open.lowerBound..<close.upperBound))
            }
            searchStart = close.upperBound
        }
        return result
    }
}

/// Postman-compatible dynamic variables, evaluated per occurrence.
public enum DynamicVariables {
    public static let names = ["$guid", "$randomUUID", "$timestamp", "$isoTimestamp", "$randomInt", "$randomBoolean"]

    public static func value(for name: String) -> String? {
        switch name {
        case "$guid", "$randomUUID":
            return UUID().uuidString.lowercased()
        case "$timestamp":
            return String(Int(Date().timeIntervalSince1970))
        case "$isoTimestamp":
            return Date().ISO8601Format(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        case "$randomInt":
            return String(Int.random(in: 0...1000))
        case "$randomBoolean":
            return Bool.random() ? "true" : "false"
        default:
            return nil
        }
    }
}
