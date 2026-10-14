import Foundation

public struct SwiftURLSessionGenerator: CodeGenerator {
    public let id = "swift"
    public let displayName = "Swift - URLSession"

    public init() {}

    public func generate(_ request: ResolvedRequest) -> String {
        var lines = ["import Foundation", ""]
        lines.append("var request = URLRequest(url: URL(string: \(Escaping.swiftQuoted(request.url.absoluteString)))!)")
        lines.append("request.httpMethod = \(Escaping.swiftQuoted(request.method.rawValue))")
        if request.settings.timeout > 0 {
            lines.append("request.timeoutInterval = \(formatNumber(request.settings.timeout))")
        }
        for header in request.headers {
            lines.append("request.addValue(\(Escaping.swiftQuoted(header.value)), forHTTPHeaderField: \(Escaping.swiftQuoted(header.name)))")
        }

        switch request.body {
        case .none:
            break
        case .text(let text):
            lines.append("")
            lines.append("request.httpBody = Data(\(literal(text)).utf8)")
        case .urlEncoded(let pairs):
            lines.append("")
            lines.append("request.httpBody = Data(\(Escaping.swiftQuoted(RequestBuilder.formURLEncoded(pairs))).utf8)")
        case .multipart(let parts):
            lines.append("")
            lines.append("let boundary = \"Boundary-\\(UUID().uuidString)\"")
            lines.append("request.setValue(\"multipart/form-data; boundary=\\(boundary)\", forHTTPHeaderField: \"Content-Type\")")
            lines.append("var body = Data()")
            for part in parts {
                lines.append("body.append(Data(\"--\\(boundary)\\r\\n\".utf8))")
                switch part.content {
                case .text(let value):
                    lines.append("body.append(Data(\(Escaping.swiftQuoted("Content-Disposition: form-data; name=\"\(part.name)\"\r\n\r\n")).utf8))")
                    lines.append("body.append(Data(\(Escaping.swiftQuoted(value)).utf8))")
                case .file(let path):
                    let filename = (path as NSString).lastPathComponent
                    let type = part.contentType ?? MultipartEncoder.mimeType(forPath: path)
                    lines.append("body.append(Data(\(Escaping.swiftQuoted("Content-Disposition: form-data; name=\"\(part.name)\"; filename=\"\(filename)\"\r\nContent-Type: \(type)\r\n\r\n")).utf8))")
                    lines.append("body.append(try Data(contentsOf: URL(fileURLWithPath: \(Escaping.swiftQuoted(path)))))")
                }
                lines.append("body.append(Data(\"\\r\\n\".utf8))")
            }
            lines.append("body.append(Data(\"--\\(boundary)--\\r\\n\".utf8))")
            lines.append("request.httpBody = body")
        case .file(let path):
            lines.append("")
            lines.append("request.httpBody = try Data(contentsOf: URL(fileURLWithPath: \(Escaping.swiftQuoted(path))))")
        }

        lines.append("")
        lines.append("let (data, response) = try await URLSession.shared.data(for: request)")
        lines.append("if let http = response as? HTTPURLResponse {")
        lines.append("    print(\"Status:\", http.statusCode)")
        lines.append("}")
        lines.append("print(String(decoding: data, as: UTF8.self))")
        return lines.joined(separator: "\n")
    }

    /// A multi-line string literal for multi-line text, otherwise a plain literal.
    private func literal(_ text: String) -> String {
        guard text.contains("\n"), !text.contains("\r") else { return Escaping.swiftQuoted(text) }
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"\"\"", with: "\\\"\"\"")
        return "\"\"\"\n" + escaped + "\n\"\"\""
    }

    private func formatNumber(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}
