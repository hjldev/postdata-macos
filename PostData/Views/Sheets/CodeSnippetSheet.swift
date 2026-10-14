import AppKit
import PostDataKit
import SwiftUI

/// Shows the request as cURL / Swift / JavaScript / Python code, with variables substituted.
struct CodeSnippetSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let state: RequestTabState
    @AppStorage(AppSettings.codeGeneratorKey) private var generatorID = "curl"
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("代码片段").font(.title2.bold())
                Spacer()
                Picker("语言", selection: $generatorID) {
                    ForEach(CodeGenerators.all, id: \.id) { generator in
                        Text(generator.displayName).tag(generator.id)
                    }
                }
                .fixedSize()
            }

            switch code {
            case .success(let code):
                CodeTextView(text: .constant(code), isEditable: false, wrapsLines: false)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
            case .failure(let error):
                ContentUnavailableView("无法生成代码", systemImage: "exclamationmark.triangle", description: Text(error.localizedDescription))
            }

            HStack {
                Text("变量已替换为当前环境中的值。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(copied ? "已复制" : "复制") {
                    if case .success(let code) = code {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(code, forType: .string)
                        copied = true
                    }
                }
                .disabled((try? code.get()) == nil)
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 680, height: 480)
        .onChange(of: generatorID) { copied = false }
    }

    private var code: Result<String, any Error> {
        Result {
            let resolved = try model.resolve(state)
            let generator = CodeGenerators.generator(id: generatorID) ?? CurlGenerator()
            return generator.generate(resolved)
        }
    }
}
