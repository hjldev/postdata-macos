import Foundation

/// Produces a code snippet that sends a resolved request.
public protocol CodeGenerator: Sendable {
    var id: String { get }
    var displayName: String { get }
    func generate(_ request: ResolvedRequest) -> String
}

public enum CodeGenerators {
    public static let all: [any CodeGenerator] = [
        CurlGenerator(),
        SwiftURLSessionGenerator(),
        JavaScriptFetchGenerator(),
        PythonRequestsGenerator(),
    ]

    public static func generator(id: String) -> (any CodeGenerator)? {
        all.first { $0.id == id }
    }
}

/// String literal escaping shared by generators.
enum Escaping {
    /// A double-quoted literal valid in Swift, JavaScript and Python.
    static func doubleQuoted(_ text: String) -> String {
        var result = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default:
                if scalar.value < 0x20 {
                    result += String(format: "\\u%04x", scalar.value)
                } else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result + "\""
    }

    /// Like `doubleQuoted` but uses Swift's `\u{…}` escape for control characters.
    static func swiftQuoted(_ text: String) -> String {
        var result = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default:
                if scalar.value < 0x20 {
                    result += "\\u{\(String(scalar.value, radix: 16))}"
                } else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result + "\""
    }
}
