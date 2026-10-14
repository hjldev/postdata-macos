import PostDataKit
import SwiftUI

extension HTTPMethod {
    var color: Color {
        switch rawValue {
        case "GET": .green
        case "POST": .orange
        case "PUT": .blue
        case "PATCH": .purple
        case "DELETE": .red
        case "HEAD": .teal
        case "OPTIONS": .pink
        default: .gray
        }
    }

    /// Short form for narrow places like the sidebar.
    var abbreviation: String {
        switch rawValue {
        case "DELETE": "DEL"
        case "OPTIONS": "OPT"
        default: rawValue.count > 5 ? String(rawValue.prefix(4)) : rawValue
        }
    }
}

struct MethodLabel: View {
    let method: HTTPMethod
    var compact = true

    var body: some View {
        Text(compact ? method.abbreviation : method.rawValue)
            .font(.system(size: compact ? 9.5 : 12, weight: .bold, design: .monospaced))
            .foregroundStyle(method.color)
            .frame(width: compact ? 34 : nil, alignment: .leading)
            .lineLimit(1)
    }
}

extension Int {
    /// Status code color: 2xx green, 3xx blue, 4xx orange, 5xx red.
    var statusColor: Color {
        switch self {
        case 200..<300: .green
        case 300..<400: .blue
        case 400..<500: .orange
        case 500..<600: .red
        default: .secondary
        }
    }
}

enum Formatters {
    static func bytes(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        seconds < 1 ? "\(Int((seconds * 1000).rounded())) ms" : String(format: "%.2f s", seconds)
    }
}
