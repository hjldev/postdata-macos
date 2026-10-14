import Foundation

/// Re-indents JSON text without parsing it into dictionaries, so key order and number
/// precision are preserved exactly (unlike `JSONSerialization`).
public enum JSONFormatter {
    /// Pretty-prints JSON; nil when the text is not valid JSON.
    public static func prettyPrint(_ text: String, indent: Int = 2) -> String? {
        format(text, indent: indent)
    }

    /// Removes all insignificant whitespace; nil when the text is not valid JSON.
    public static func minify(_ text: String) -> String? {
        format(text, indent: nil)
    }

    public static func isValid(_ text: String) -> Bool {
        minify(text) != nil
    }

    private static func format(_ text: String, indent: Int?) -> String? {
        var parser = Parser(input: Array(text.utf8), indent: indent)
        guard parser.formatDocument() else { return nil }
        return String(decoding: parser.output, as: UTF8.self)
    }

    private struct Parser {
        let input: [UInt8]
        let indent: Int?
        var position = 0
        var output: [UInt8] = []
        var depth = 0
        let maxDepth = 512

        init(input: [UInt8], indent: Int?) {
            self.input = input
            self.indent = indent
            output.reserveCapacity(input.count + input.count / 4)
        }

        mutating func formatDocument() -> Bool {
            // Skip a UTF-8 byte order mark.
            if input.starts(with: [0xEF, 0xBB, 0xBF]) { position = 3 }
            skipWhitespace()
            guard value() else { return false }
            skipWhitespace()
            return position == input.count
        }

        mutating func skipWhitespace() {
            while position < input.count {
                switch input[position] {
                case 0x20, 0x09, 0x0A, 0x0D: position += 1
                default: return
                }
            }
        }

        mutating func newline() {
            guard let indent else { return }
            output.append(0x0A)
            output.append(contentsOf: repeatElement(0x20, count: indent * depth))
        }

        mutating func value() -> Bool {
            guard position < input.count else { return false }
            switch input[position] {
            case UInt8(ascii: "{"): return object()
            case UInt8(ascii: "["): return array()
            case UInt8(ascii: "\""): return string()
            case UInt8(ascii: "t"): return literal("true")
            case UInt8(ascii: "f"): return literal("false")
            case UInt8(ascii: "n"): return literal("null")
            case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return number()
            default: return false
            }
        }

        mutating func object() -> Bool {
            depth += 1
            guard depth <= maxDepth else { return false }
            position += 1
            output.append(UInt8(ascii: "{"))
            skipWhitespace()
            if position < input.count, input[position] == UInt8(ascii: "}") {
                position += 1
                depth -= 1
                output.append(UInt8(ascii: "}"))
                return true
            }
            while true {
                newline()
                skipWhitespace()
                guard position < input.count, input[position] == UInt8(ascii: "\""), string() else { return false }
                skipWhitespace()
                guard position < input.count, input[position] == UInt8(ascii: ":") else { return false }
                position += 1
                output.append(UInt8(ascii: ":"))
                if indent != nil { output.append(0x20) }
                skipWhitespace()
                guard value() else { return false }
                skipWhitespace()
                guard position < input.count else { return false }
                if input[position] == UInt8(ascii: ",") {
                    position += 1
                    output.append(UInt8(ascii: ","))
                    continue
                }
                if input[position] == UInt8(ascii: "}") {
                    position += 1
                    depth -= 1
                    newline()
                    output.append(UInt8(ascii: "}"))
                    return true
                }
                return false
            }
        }

        mutating func array() -> Bool {
            depth += 1
            guard depth <= maxDepth else { return false }
            position += 1
            output.append(UInt8(ascii: "["))
            skipWhitespace()
            if position < input.count, input[position] == UInt8(ascii: "]") {
                position += 1
                depth -= 1
                output.append(UInt8(ascii: "]"))
                return true
            }
            while true {
                newline()
                skipWhitespace()
                guard value() else { return false }
                skipWhitespace()
                guard position < input.count else { return false }
                if input[position] == UInt8(ascii: ",") {
                    position += 1
                    output.append(UInt8(ascii: ","))
                    continue
                }
                if input[position] == UInt8(ascii: "]") {
                    position += 1
                    depth -= 1
                    newline()
                    output.append(UInt8(ascii: "]"))
                    return true
                }
                return false
            }
        }

        /// Copies a string token verbatim, validating escapes.
        mutating func string() -> Bool {
            let start = position
            position += 1
            while position < input.count {
                let c = input[position]
                if c == UInt8(ascii: "\"") {
                    position += 1
                    output.append(contentsOf: input[start..<position])
                    return true
                }
                if c == UInt8(ascii: "\\") {
                    guard position + 1 < input.count else { return false }
                    let escaped = input[position + 1]
                    switch escaped {
                    case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"),
                         UInt8(ascii: "b"), UInt8(ascii: "f"), UInt8(ascii: "n"), UInt8(ascii: "r"), UInt8(ascii: "t"):
                        position += 2
                    case UInt8(ascii: "u"):
                        guard position + 5 < input.count,
                              input[(position + 2)...(position + 5)].allSatisfy(Self.isHexDigit) else { return false }
                        position += 6
                    default:
                        return false
                    }
                    continue
                }
                if c < 0x20 { return false } // unescaped control character
                position += 1
            }
            return false
        }

        static func isHexDigit(_ c: UInt8) -> Bool {
            (c >= 48 && c <= 57) || (c >= 65 && c <= 70) || (c >= 97 && c <= 102)
        }

        mutating func literal(_ word: StaticString) -> Bool {
            let bytes = UnsafeBufferPointer(start: word.utf8Start, count: word.utf8CodeUnitCount)
            guard position + bytes.count <= input.count,
                  input[position..<(position + bytes.count)].elementsEqual(bytes) else { return false }
            output.append(contentsOf: bytes)
            position += bytes.count
            return true
        }

        mutating func number() -> Bool {
            let start = position
            func digit(_ i: Int) -> Bool { i < input.count && input[i] >= 48 && input[i] <= 57 }
            if input[position] == UInt8(ascii: "-") { position += 1 }
            guard digit(position) else { return false }
            if input[position] == UInt8(ascii: "0") {
                position += 1
            } else {
                while digit(position) { position += 1 }
            }
            if position < input.count, input[position] == UInt8(ascii: ".") {
                position += 1
                guard digit(position) else { return false }
                while digit(position) { position += 1 }
            }
            if position < input.count, input[position] == UInt8(ascii: "e") || input[position] == UInt8(ascii: "E") {
                position += 1
                if position < input.count, input[position] == UInt8(ascii: "+") || input[position] == UInt8(ascii: "-") {
                    position += 1
                }
                guard digit(position) else { return false }
                while digit(position) { position += 1 }
            }
            output.append(contentsOf: input[start..<position])
            return true
        }
    }
}
