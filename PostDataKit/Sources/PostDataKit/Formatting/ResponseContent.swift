import Foundation

/// How a response body should be displayed, computed once off the main thread.
public struct ResponseContent: Sendable {
    public enum Kind: Hashable, Sendable {
        case json, html, xml, text, image, binary
    }

    public var kind: Kind
    /// Decoded body text; nil for images and binary data.
    public var text: String?
    /// Pretty-printed JSON; nil when the body is not JSON.
    public var prettyText: String?

    public init(kind: Kind, text: String?, prettyText: String?) {
        self.kind = kind
        self.text = text
        self.prettyText = prettyText
    }

    /// The text to show in "Pretty" mode.
    public var displayText: String { prettyText ?? text ?? "" }

    public static func make(from response: HTTPResponse) -> ResponseContent {
        let type = (response.contentType ?? "").lowercased()
        let body = response.body
        if type.hasPrefix("image/") {
            return ResponseContent(kind: .image, text: nil, prettyText: nil)
        }
        guard !body.isEmpty else {
            return ResponseContent(kind: .text, text: "", prettyText: nil)
        }
        let declaredText = type.contains("json") || type.contains("xml") || type.contains("html")
            || type.hasPrefix("text/") || type.contains("javascript") || type.contains("x-www-form-urlencoded")
        if !declaredText, looksBinary(body) {
            return ResponseContent(kind: .binary, text: nil, prettyText: nil)
        }
        guard let text = response.bodyText else {
            return ResponseContent(kind: .binary, text: nil, prettyText: nil)
        }
        if type.contains("json") || (!declaredText && looksLikeJSON(text)) || (type.hasPrefix("text/plain") && looksLikeJSON(text)) {
            if let pretty = JSONFormatter.prettyPrint(text) {
                return ResponseContent(kind: .json, text: text, prettyText: pretty)
            }
        }
        if type.contains("html") { return ResponseContent(kind: .html, text: text, prettyText: nil) }
        if type.contains("xml") { return ResponseContent(kind: .xml, text: text, prettyText: nil) }
        return ResponseContent(kind: .text, text: text, prettyText: nil)
    }

    static func looksLikeJSON(_ text: String) -> Bool {
        guard let first = text.first(where: { !$0.isWhitespace }) else { return false }
        return first == "{" || first == "["
    }

    /// NUL bytes in the first 8 KB or invalid UTF-8 suggest binary data.
    static func looksBinary(_ data: Data) -> Bool {
        let prefix = data.prefix(8192)
        if prefix.contains(0) { return true }
        return String(data: data, encoding: .utf8) == nil
    }
}
