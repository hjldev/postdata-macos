import Foundation

public enum SyntaxTokenKind: Hashable, Sendable {
    case key, string, number, keyword, punctuation, variable
}

/// A highlighted span. `location`/`length` are UTF-16 offsets, ready for `NSRange`.
public struct SyntaxToken: Hashable, Sendable {
    public var kind: SyntaxTokenKind
    public var location: Int
    public var length: Int

    public init(kind: SyntaxTokenKind, location: Int, length: Int) {
        self.kind = kind
        self.location = location
        self.length = length
    }
}

/// A lenient JSON lexer for syntax highlighting. It never fails: partially typed or invalid
/// JSON still gets highlighted as far as it makes sense.
public enum JSONTokenizer {
    public static func tokenize(_ text: String) -> [SyntaxToken] {
        let units = Array(text.utf16)
        var tokens: [SyntaxToken] = []
        var i = 0
        let n = units.count

        func isDigitStart(_ c: UInt16) -> Bool { (c >= 48 && c <= 57) || c == 45 }
        func isNumberChar(_ c: UInt16) -> Bool {
            (c >= 48 && c <= 57) || c == 45 || c == 43 || c == 46 || c == 101 || c == 69
        }
        func isLetter(_ c: UInt16) -> Bool { (c >= 97 && c <= 122) || (c >= 65 && c <= 90) }

        while i < n {
            let c = units[i]
            switch c {
            case 34: // "
                let start = i
                i += 1
                while i < n {
                    if units[i] == 92 { i += 2; continue } // backslash escape
                    if units[i] == 34 { i += 1; break }
                    if units[i] == 10 { break } // unterminated at line end
                    i += 1
                }
                i = min(i, n)
                // A string followed by ':' is an object key.
                var j = i
                while j < n, units[j] == 32 || units[j] == 9 || units[j] == 10 || units[j] == 13 { j += 1 }
                let kind: SyntaxTokenKind = (j < n && units[j] == 58) ? .key : .string
                tokens.append(SyntaxToken(kind: kind, location: start, length: i - start))
            case 123, 125, 91, 93, 58, 44: // { } [ ] : ,
                tokens.append(SyntaxToken(kind: .punctuation, location: i, length: 1))
                i += 1
            default:
                if isDigitStart(c) {
                    let start = i
                    i += 1
                    while i < n, isNumberChar(units[i]) { i += 1 }
                    tokens.append(SyntaxToken(kind: .number, location: start, length: i - start))
                } else if isLetter(c) {
                    let start = i
                    while i < n, isLetter(units[i]) { i += 1 }
                    let word = String(utf16CodeUnits: Array(units[start..<i]), count: i - start)
                    if word == "true" || word == "false" || word == "null" {
                        tokens.append(SyntaxToken(kind: .keyword, location: start, length: i - start))
                    }
                } else {
                    i += 1
                }
            }
        }
        return tokens
    }

    /// Spans of `{{variable}}` placeholders.
    public static func variableTokens(in text: String) -> [SyntaxToken] {
        let units = Array(text.utf16)
        var tokens: [SyntaxToken] = []
        var i = 0
        while i + 1 < units.count {
            if units[i] == 123, units[i + 1] == 123 {
                var j = i + 2
                var found = false
                while j + 1 < units.count {
                    if units[j] == 10 { break }
                    if units[j] == 125, units[j + 1] == 125 { found = true; break }
                    j += 1
                }
                if found, j > i + 2 {
                    tokens.append(SyntaxToken(kind: .variable, location: i, length: j + 2 - i))
                    i = j + 2
                    continue
                }
            }
            i += 1
        }
        return tokens
    }
}
