import AppKit
import PostDataKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

private enum BodyDisplayMode: String, CaseIterable, Identifiable {
    case pretty, raw, preview
    var id: String { rawValue }

    var title: String {
        switch self {
        case .pretty: "Pretty"
        case .raw: "Raw"
        case .preview: "Preview"
        }
    }
}

struct ResponseBodyView: View {
    let loaded: LoadedResponse
    @State private var mode: BodyDisplayMode = Self.initialMode
    @AppStorage(AppSettings.wrapLinesKey) private var wrapLines = true
    @AppStorage(AppSettings.editorFontSizeKey) private var fontSize = 12.0

    private var content: ResponseContent { loaded.content }

    private static var initialMode: BodyDisplayMode {
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: "PostDataDebugBodyMode"), let mode = BodyDisplayMode(rawValue: raw) {
            return mode
        }
        #endif
        return .pretty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Picker("", selection: $mode) {
                    ForEach(BodyDisplayMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .controlSize(.small)
                Text(kindLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.12)))
                Spacer()
                Toggle(isOn: $wrapLines) {
                    Image(systemName: "text.word.spacing")
                }
                .toggleStyle(.button)
                .controlSize(.small)
                .help("自动换行")
                Button {
                    copyBody()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .controlSize(.small)
                .help("复制响应内容")
                Button {
                    saveBody()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .controlSize(.small)
                .help("保存响应到文件")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)

            Divider()

            Group {
                switch content.kind {
                case .image:
                    imagePreview
                case .binary:
                    ContentUnavailableView {
                        Label("二进制内容", systemImage: "doc.zipper")
                    } description: {
                        Text("\(Formatters.bytes(loaded.response.bodySize))，无法以文本显示。")
                    } actions: {
                        Button("保存到文件…") { saveBody() }
                    }
                default:
                    textContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var textContent: some View {
        switch mode {
        case .pretty:
            CodeTextView(
                text: .constant(content.displayText),
                isEditable: false,
                language: content.kind == .json ? .json : .plain,
                wrapsLines: wrapLines,
                fontSize: fontSize
            )
        case .raw:
            CodeTextView(text: .constant(content.text ?? ""), isEditable: false, wrapsLines: wrapLines, fontSize: fontSize)
        case .preview:
            if content.kind == .html {
                HTMLPreview(html: content.text ?? "", baseURL: loaded.response.url)
            } else {
                CodeTextView(text: .constant(content.text ?? ""), isEditable: false, wrapsLines: true, fontSize: fontSize)
            }
        }
    }

    @ViewBuilder
    private var imagePreview: some View {
        if let image = NSImage(data: loaded.response.body) {
            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: image.size.width, maxHeight: image.size.height)
                    .padding()
            }
        } else {
            ContentUnavailableView("无法解码图片", systemImage: "photo")
        }
    }

    private var kindLabel: String {
        switch content.kind {
        case .json: "JSON"
        case .html: "HTML"
        case .xml: "XML"
        case .text: "Text"
        case .image: "Image"
        case .binary: "Binary"
        }
    }

    private func copyBody() {
        NSPasteboard.general.clearContents()
        if let text = mode == .raw ? content.text : (content.prettyText ?? content.text) {
            NSPasteboard.general.setString(text, forType: .string)
        } else if let image = NSImage(data: loaded.response.body) {
            NSPasteboard.general.writeObjects([image])
        }
    }

    private func saveBody() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedFilename
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? loaded.response.body.write(to: url, options: .atomic)
    }

    private var suggestedFilename: String {
        let last = loaded.response.url?.lastPathComponent ?? ""
        if !last.isEmpty, last != "/", last.contains(".") { return last }
        let ext = loaded.response.mimeType.flatMap { UTType(mimeType: $0)?.preferredFilenameExtension } ?? "txt"
        return "response.\(ext)"
    }
}

/// Renders HTML responses with JavaScript disabled and a non-persistent data store.
private struct HTMLPreview: View {
    let html: String
    let baseURL: URL?
    @State private var page: WebPage = {
        var configuration = WebPage.Configuration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultNavigationPreferences.allowsContentJavaScript = false
        return WebPage(configuration: configuration)
    }()

    var body: some View {
        WebView(page)
            .task(id: html) {
                page.load(html: html, baseURL: baseURL ?? URL(string: "about:blank")!)
            }
    }
}
