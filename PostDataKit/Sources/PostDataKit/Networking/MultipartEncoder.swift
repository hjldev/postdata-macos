import Foundation
import UniformTypeIdentifiers

/// Encodes multipart/form-data bodies (RFC 7578).
public struct MultipartEncoder: Sendable {
    public let boundary: String

    public init(boundary: String = "PostDataFormBoundary" + UUID().uuidString.replacingOccurrences(of: "-", with: "")) {
        self.boundary = boundary
    }

    public var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    public func encode(_ parts: [ResolvedRequest.MultipartPart], readFile: (String) throws -> Data) throws -> Data {
        var data = Data()
        for part in parts {
            data.append("--\(boundary)\r\n")
            switch part.content {
            case .text(let text):
                data.append("Content-Disposition: form-data; name=\"\(Self.escape(part.name))\"\r\n")
                if let contentType = part.contentType {
                    data.append("Content-Type: \(contentType)\r\n")
                }
                data.append("\r\n")
                data.append(text)
            case .file(let path):
                let filename = (path as NSString).lastPathComponent
                data.append("Content-Disposition: form-data; name=\"\(Self.escape(part.name))\"; filename=\"\(Self.escape(filename))\"\r\n")
                data.append("Content-Type: \(part.contentType ?? Self.mimeType(forPath: path))\r\n")
                data.append("\r\n")
                data.append(try readFile(path))
            }
            data.append("\r\n")
        }
        data.append("--\(boundary)--\r\n")
        return data
    }

    /// MIME type from the file extension, defaulting to application/octet-stream.
    public static func mimeType(forPath path: String) -> String {
        let ext = (path as NSString).pathExtension
        guard !ext.isEmpty, let type = UTType(filenameExtension: ext), let mime = type.preferredMIMEType else {
            return "application/octet-stream"
        }
        return mime
    }

    /// Quotes and line breaks would break the header; percent-encode them as browsers do.
    static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\"", with: "%22")
            .replacingOccurrences(of: "\r", with: "%0D")
            .replacingOccurrences(of: "\n", with: "%0A")
    }
}

extension Data {
    mutating func append(_ string: String) {
        append(contentsOf: Array(string.utf8))
    }
}
