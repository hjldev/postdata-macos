import Foundation

/// Keeps the URL text field and the Params table in sync.
///
/// Works on plain strings because a URL containing `{{variables}}` is not a valid `URL` yet.
/// Nothing is percent-decoded: what the user typed is what they see in the table.
public enum URLQuerySync {
    /// Splits a URL into the part before `?`, the query (without `?`) and the fragment (without `#`).
    public static func split(_ url: String) -> (base: String, query: String?, fragment: String?) {
        var rest = Substring(url)
        var fragment: String?
        if let hash = rest.firstIndex(of: "#") {
            fragment = String(rest[rest.index(after: hash)...])
            rest = rest[..<hash]
        }
        guard let question = rest.firstIndex(of: "?") else {
            return (String(rest), nil, fragment)
        }
        return (String(rest[..<question]), String(rest[rest.index(after: question)...]), fragment)
    }

    /// Parses `a=1&b&c=` into pairs. A missing `=` yields an empty value.
    public static func parseQuery(_ query: String) -> [(key: String, value: String)] {
        query.split(separator: "&", omittingEmptySubsequences: true).map { pair in
            if let equals = pair.firstIndex(of: "=") {
                return (String(pair[..<equals]), String(pair[pair.index(after: equals)...]))
            }
            return (String(pair), "")
        }
    }

    /// The params table after the URL text changed. Disabled rows keep their position;
    /// enabled rows are matched positionally to the URL's pairs so row identity (and focus) survives typing.
    public static func params(fromURL url: String, existing: [KeyValue]) -> [KeyValue] {
        let parsed = split(url).query.map(parseQuery) ?? []
        var remaining = parsed[...]
        var result: [KeyValue] = []
        for param in existing {
            if !param.isEnabled {
                result.append(param)
            } else if let next = remaining.popFirst() {
                result.append(KeyValue(id: param.id, key: next.key, value: next.value, isEnabled: true, description: param.description))
            }
        }
        for pair in remaining {
            result.append(KeyValue(key: pair.key, value: pair.value))
        }
        return result
    }

    /// The URL after the params table changed: the query is rebuilt from enabled rows.
    public static func url(_ url: String, replacingQueryWith params: [KeyValue]) -> String {
        let (base, _, fragment) = split(url)
        let pairs = params.filter { $0.isEnabled && !($0.key.isEmpty && $0.value.isEmpty) }
            .map { $0.value.isEmpty ? $0.key : "\($0.key)=\($0.value)" }
        var result = base
        if !pairs.isEmpty { result += "?" + pairs.joined(separator: "&") }
        if let fragment { result += "#" + fragment }
        return result
    }
}
