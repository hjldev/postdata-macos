import PostDataKit
import SwiftUI
import UniformTypeIdentifiers

/// Import a Postman collection/environment file, or paste JSON or a cURL command.
struct ImportSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var isPickingFile = false
    @State private var isDropTargeted = false
    @State private var errorMessage: String?
    @State private var outcome: ImportOutcome?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("导入").font(.title2.bold())
            Text("支持 Postman Collection v2.0 / v2.1、Postman Environment / Globals 文件，以及 cURL 命令。")
                .foregroundStyle(.secondary)

            if let outcome {
                OutcomeView(outcome: outcome)
            } else {
                dropZone
                Text("或粘贴 JSON / cURL：").font(.callout.weight(.medium))
                CodeTextView(text: $text, wrapsLines: true)
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
                if let errorMessage {
                    Label(errorMessage, systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }

            HStack {
                Spacer()
                if outcome != nil {
                    Button("完成") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("取消") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button("导入") { run { try model.importText(text) } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(20)
        .frame(width: 580)
        .fileImporter(isPresented: $isPickingFile, allowedContentTypes: [.json, .plainText, .data]) { result in
            switch result {
            case .success(let url): importFile(url)
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
    }

    private var dropZone: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("将文件拖放到这里")
            Button("选择文件…") { isPickingFile = true }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .foregroundStyle(isDropTargeted ? Color.accentColor : Color(nsColor: .separatorColor))
        )
        .background(RoundedRectangle(cornerRadius: 10).fill(isDropTargeted ? Color.accentColor.opacity(0.08) : .clear))
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            importFile(url)
            return true
        } isTargeted: { isDropTargeted = $0 }
    }

    private func importFile(_ url: URL) {
        run {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            return try model.importData(try Data(contentsOf: url))
        }
    }

    private func run(_ work: () throws -> ImportOutcome) {
        errorMessage = nil
        do {
            let result = try work()
            switch result {
            case .curl:
                dismiss()
            case .collection(_, _, let warnings) where warnings.isEmpty:
                dismiss()
            default:
                outcome = result
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct OutcomeView: View {
    let outcome: ImportOutcome

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch outcome {
            case .collection(let name, let count, let warnings):
                Label("已导入集合「\(name)」，共 \(count) 个请求。", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                if !warnings.isEmpty {
                    Text("以下内容未能完整导入：").font(.callout.weight(.medium))
                    ForEach(warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.callout)
                    }
                }
            case .environment(let name, let count):
                Label("已导入环境「\(name)」，共 \(count) 个变量。", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .curl:
                Label("已从 cURL 创建请求。", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
    }
}
