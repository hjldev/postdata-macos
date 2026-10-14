import Foundation

public struct JavaScriptFetchGenerator: CodeGenerator {
    public let id = "javascript-fetch"
    public let displayName = "JavaScript - Fetch"

    public init() {}

    public func generate(_ request: ResolvedRequest) -> String {
        var lines: [String] = []
        var options: [String] = ["  method: \(Escaping.doubleQuoted(request.method.rawValue))"]

        if !request.headers.isEmpty {
            lines.append("const myHeaders = new Headers();")
            for header in request.headers {
                lines.append("myHeaders.append(\(Escaping.doubleQuoted(header.name)), \(Escaping.doubleQuoted(header.value)));")
            }
            lines.append("")
            options.append("  headers: myHeaders")
        }

        switch request.body {
        case .none:
            break
        case .text(let text):
            if request.headers.value(for: "Content-Type")?.contains("json") == true,
               let minified = JSONFormatter.minify(text) {
                lines.append("const raw = JSON.stringify(\(minified));")
            } else {
                lines.append("const raw = \(Escaping.doubleQuoted(text));")
            }
            lines.append("")
            options.append("  body: raw")
        case .urlEncoded(let pairs):
            lines.append("const urlencoded = new URLSearchParams();")
            for pair in pairs {
                lines.append("urlencoded.append(\(Escaping.doubleQuoted(pair.name)), \(Escaping.doubleQuoted(pair.value)));")
            }
            lines.append("")
            options.append("  body: urlencoded")
        case .multipart(let parts):
            lines.append("const formdata = new FormData();")
            for part in parts {
                switch part.content {
                case .text(let value):
                    lines.append("formdata.append(\(Escaping.doubleQuoted(part.name)), \(Escaping.doubleQuoted(value)));")
                case .file(let path):
                    lines.append("formdata.append(\(Escaping.doubleQuoted(part.name)), fileInput.files[0], \(Escaping.doubleQuoted((path as NSString).lastPathComponent)));")
                }
            }
            lines.append("")
            options.append("  body: formdata")
        case .file:
            lines.append("const file = \"<file contents here>\";")
            lines.append("")
            options.append("  body: file")
        }

        options.append("  redirect: \(request.settings.followRedirects ? "\"follow\"" : "\"manual\"")")
        lines.append("const requestOptions = {")
        lines.append(options.joined(separator: ",\n"))
        lines.append("};")
        lines.append("")
        lines.append("fetch(\(Escaping.doubleQuoted(request.url.absoluteString)), requestOptions)")
        lines.append("  .then((response) => response.text())")
        lines.append("  .then((result) => console.log(result))")
        lines.append("  .catch((error) => console.error(error));")
        return lines.joined(separator: "\n")
    }
}
