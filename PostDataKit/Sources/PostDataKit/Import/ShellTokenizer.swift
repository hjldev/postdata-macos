import Foundation

public enum ShellTokenizerError: LocalizedError, Equatable {
    case unterminatedQuote

    public var errorDescription: String? {
        switch self {
        case .unterminatedQuote: "命令中有未闭合的引号"
        }
    }
}

/// Splits a command line into words like a POSIX shell (without expansion):
/// single quotes, double quotes, `$'…'` ANSI-C quotes, backslash escapes and line continuations.
public enum ShellTokenizer {
    public static func tokenize(_ input: String) throws -> [String] {
        var tokens: [String] = []
        var current = ""
        var inToken = false
        // "\r\n" is a single Character in Swift, so normalize line endings before splitting.
        // Windows `^` and PowerShell backtick continuations are not handled.
        let chars = Array(input.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n"))
        var i = 0

        func flush() {
            if inToken { tokens.append(current) }
            current = ""
            inToken = false
        }

        while i < chars.count {
            let c = chars[i]
            switch c {
            case " ", "\t", "\n":
                flush()
                i += 1
            case "\\":
                if i + 1 < chars.count {
                    if chars[i + 1] == "\n" {
                        i += 2 // line continuation
                    } else {
                        current.append(chars[i + 1])
                        inToken = true
                        i += 2
                    }
                } else {
                    i += 1
                }
            case "'":
                inToken = true
                i += 1
                guard let end = chars[i...].firstIndex(of: "'") else { throw ShellTokenizerError.unterminatedQuote }
                current.append(contentsOf: chars[i..<end])
                i = end + 1
            case "\"":
                inToken = true
                i += 1
                var closed = false
                while i < chars.count {
                    let d = chars[i]
                    if d == "\"" { closed = true; i += 1; break }
                    if d == "\\", i + 1 < chars.count {
                        let next = chars[i + 1]
                        switch next {
                        case "\"", "\\", "$", "`": current.append(next); i += 2
                        case "\n": i += 2
                        default: current.append(d); i += 1
                        }
                        continue
                    }
                    current.append(d)
                    i += 1
                }
                if !closed { throw ShellTokenizerError.unterminatedQuote }
            case "$" where i + 1 < chars.count && chars[i + 1] == "'":
                inToken = true
                i += 2
                var closed = false
                while i < chars.count {
                    let d = chars[i]
                    if d == "'" { closed = true; i += 1; break }
                    if d == "\\", i + 1 < chars.count {
                        let (decoded, consumed) = ansiEscape(chars, at: i + 1)
                        current.append(decoded)
                        i += 1 + consumed
                        continue
                    }
                    current.append(d)
                    i += 1
                }
                if !closed { throw ShellTokenizerError.unterminatedQuote }
            default:
                current.append(c)
                inToken = true
                i += 1
            }
        }
        flush()
        return tokens
    }

    /// Decodes the escape starting after a backslash inside `$'…'`. Returns the text and characters consumed.
    private static func ansiEscape(_ chars: [Character], at index: Int) -> (String, Int) {
        let c = chars[index]
        switch c {
        case "n": return ("\n", 1)
        case "t": return ("\t", 1)
        case "r": return ("\r", 1)
        case "\\": return ("\\", 1)
        case "'": return ("'", 1)
        case "\"": return ("\"", 1)
        case "a": return ("\u{07}", 1)
        case "b": return ("\u{08}", 1)
        case "e", "E": return ("\u{1B}", 1)
        case "f": return ("\u{0C}", 1)
        case "v": return ("\u{0B}", 1)
        case "x":
            return hexEscape(chars, from: index + 1, maxDigits: 2, prefixLength: 1, fallback: "\\x")
        case "u":
            return hexEscape(chars, from: index + 1, maxDigits: 4, prefixLength: 1, fallback: "\\u")
        case "U":
            return hexEscape(chars, from: index + 1, maxDigits: 8, prefixLength: 1, fallback: "\\U")
        default:
            return ("\\" + String(c), 1)
        }
    }

    private static func hexEscape(_ chars: [Character], from start: Int, maxDigits: Int, prefixLength: Int, fallback: String) -> (String, Int) {
        var digits = ""
        var i = start
        while i < chars.count, digits.count < maxDigits, chars[i].isHexDigit {
            digits.append(chars[i])
            i += 1
        }
        guard let value = UInt32(digits, radix: 16), !digits.isEmpty else { return (fallback, prefixLength) }
        if maxDigits == 2 {
            // \xHH is a raw byte; treat bytes as Latin-1 / ASCII which covers the common cases.
            return (String(UnicodeScalar(UInt8(value))), prefixLength + digits.count)
        }
        guard let scalar = UnicodeScalar(value) else { return (fallback, prefixLength) }
        return (String(Character(scalar)), prefixLength + digits.count)
    }

    /// Quotes a word for a POSIX shell using single quotes.
    public static func quote(_ word: String) -> String {
        if !word.isEmpty, word.allSatisfy({ $0.isLetter || $0.isNumber || "-_./:=@%+,".contains($0) }), word.allSatisfy(\.isASCII) {
            return word
        }
        return "'" + word.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
