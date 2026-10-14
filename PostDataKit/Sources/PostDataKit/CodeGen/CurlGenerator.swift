import Foundation

public struct CurlGenerator: CodeGenerator {
    public let id = "curl"
    public let displayName = "cURL"

    public init() {}

    public func generate(_ request: ResolvedRequest) -> String {
        var parts: [String] = ["curl"]
        if request.settings.followRedirects { parts.append("--location") }
        if !request.settings.validateSSL { parts.append("--insecure") }

        let hasBody = request.body != .none
        if request.method == .head {
            parts.append("--head")
        } else if request.method != .get || hasBody {
            // Explicit even for POST; also needed for GET with a body, which curl would otherwise send as POST.
            parts.append("--request \(request.method.rawValue)")
        }
        var lines = [parts.joined(separator: " ") + " " + ShellTokenizer.quote(request.url.absoluteString)]

        for header in request.headers {
            lines.append("--header " + ShellTokenizer.quote("\(header.name): \(header.value)"))
        }

        switch request.body {
        case .none:
            break
        case .text(let text):
            lines.append("--data-raw " + ShellTokenizer.quote(text))
        case .urlEncoded(let pairs):
            for pair in pairs {
                lines.append("--data-urlencode " + ShellTokenizer.quote("\(pair.name)=\(pair.value)"))
            }
        case .multipart(let parts):
            for part in parts {
                switch part.content {
                case .text(let value):
                    lines.append("--form-string " + ShellTokenizer.quote("\(part.name)=\(value)"))
                case .file(let path):
                    var spec = "\(part.name)=@\"\(path)\""
                    if let type = part.contentType { spec += ";type=\(type)" }
                    lines.append("--form " + ShellTokenizer.quote(spec))
                }
            }
        case .file(let path):
            lines.append("--data-binary " + ShellTokenizer.quote("@" + path))
        }
        return lines.joined(separator: " \\\n")
    }
}
