import Foundation

public struct PythonRequestsGenerator: CodeGenerator {
    public let id = "python-requests"
    public let displayName = "Python - Requests"

    public init() {}

    public func generate(_ request: ResolvedRequest) -> String {
        var lines = ["import requests", ""]
        lines.append("url = \(Escaping.doubleQuoted(request.url.absoluteString))")
        lines.append("")

        var arguments = [Escaping.doubleQuoted(request.method.rawValue), "url"]
        var headers = request.headers

        switch request.body {
        case .none:
            break
        case .text(let text):
            lines.append("payload = \(Escaping.doubleQuoted(text))")
            arguments.append("data=payload.encode(\"utf-8\")")
        case .urlEncoded(let pairs):
            lines.append("payload = \(Escaping.doubleQuoted(RequestBuilder.formURLEncoded(pairs)))")
            arguments.append("data=payload")
        case .multipart(let parts):
            // requests generates the multipart Content-Type with its own boundary.
            headers.removeAll { $0.name.lowercased() == "content-type" }
            let texts = parts.compactMap { part -> String? in
                if case .text(let value) = part.content {
                    return "  \(Escaping.doubleQuoted(part.name)): \(Escaping.doubleQuoted(value))"
                }
                return nil
            }
            let files = parts.compactMap { part -> String? in
                if case .file(let path) = part.content {
                    let name = (path as NSString).lastPathComponent
                    let type = part.contentType ?? MultipartEncoder.mimeType(forPath: path)
                    return "  (\(Escaping.doubleQuoted(part.name)), (\(Escaping.doubleQuoted(name)), open(\(Escaping.doubleQuoted(path)), \"rb\"), \(Escaping.doubleQuoted(type))))"
                }
                return nil
            }
            lines.append("payload = {" + (texts.isEmpty ? "}" : "\n" + texts.joined(separator: ",\n") + "\n}"))
            lines.append("files = [" + (files.isEmpty ? "]" : "\n" + files.joined(separator: ",\n") + "\n]"))
            arguments.append("data=payload")
            arguments.append("files=files")
        case .file(let path):
            lines.append("payload = open(\(Escaping.doubleQuoted(path)), \"rb\")")
            arguments.append("data=payload")
        }

        if headers.isEmpty {
            lines.append("headers = {}")
        } else {
            lines.append("headers = {")
            lines.append(headers.map { "  \(Escaping.doubleQuoted($0.name)): \(Escaping.doubleQuoted($0.value))" }.joined(separator: ",\n"))
            lines.append("}")
        }
        arguments.insert("headers=headers", at: 2)
        if !request.settings.followRedirects { arguments.append("allow_redirects=False") }
        if !request.settings.validateSSL { arguments.append("verify=False") }
        if request.settings.timeout > 0 {
            let timeout = request.settings.timeout
            arguments.append("timeout=\(timeout == timeout.rounded() ? String(Int(timeout)) : String(timeout))")
        }

        lines.append("")
        lines.append("response = requests.request(\(arguments.joined(separator: ", ")))")
        lines.append("")
        lines.append("print(response.status_code)")
        lines.append("print(response.text)")
        return lines.joined(separator: "\n")
    }
}
