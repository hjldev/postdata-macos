import PostDataKit
import SwiftUI

/// Method menu, URL field (accepts pasted cURL commands), Send and Save.
struct URLBarView: View {
    @Environment(AppModel.self) private var model
    @Bindable var state: RequestTabState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                HStack(spacing: 0) {
                    MethodMenu(method: $state.draft.method)
                    Divider().frame(height: 18)
                    TextField("输入 URL，或粘贴 cURL 命令", text: urlBinding)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                        .padding(.horizontal, 10)
                        .onSubmit { model.send(state) }
                }
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor)))

                if state.response.isLoading {
                    Button(role: .cancel) {
                        state.cancel()
                    } label: {
                        Text("取消").frame(minWidth: 56)
                    }
                    .controlSize(.large)
                } else {
                    Button {
                        model.send(state)
                    } label: {
                        Text("发送").frame(minWidth: 56)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .help("发送请求 (⌘↩)")
                }

                Button {
                    model.save(state)
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .controlSize(.large)
                .help("保存 (⌘S)")
            }
            VariableHint(state: state)
        }
    }

    /// Pasting a whole cURL command imports it; typing "curl …" by hand does not.
    private var urlBinding: Binding<String> {
        Binding(
            get: { state.draft.url },
            set: { newValue in
                // The field writes its value back on focus; ignore no-op writes so focusing never dirties the tab.
                guard newValue != state.draft.url else { return }
                let isPaste = newValue.count - state.draft.url.count > 8
                if isPaste, CurlParser.looksLikeCurl(newValue), let imported = try? CurlParser.parse(newValue) {
                    state.applyImported(imported)
                } else {
                    state.draft.setURL(newValue)
                }
            }
        )
    }
}

private struct MethodMenu: View {
    @Binding var method: HTTPMethod

    var body: some View {
        Menu {
            ForEach(HTTPMethod.standard, id: \.self) { item in
                Button(item.rawValue) { method = item }
            }
        } label: {
            HStack(spacing: 4) {
                Text(method.rawValue)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(method.color)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 84, alignment: .leading)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .padding(.leading, 10)
        .fixedSize()
    }
}

/// Shows unresolved `{{variables}}` or the resolved URL below the URL field.
private struct VariableHint: View {
    @Environment(AppModel.self) private var model
    let state: RequestTabState

    var body: some View {
        let url = state.draft.url
        if url.contains("{{") {
            let result = model.store.variableResolver(collectionID: state.collectionID).resolveDetailed(url)
            if result.unresolved.isEmpty {
                Text("→ \(result.text)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .padding(.leading, 4)
            } else {
                Label("未定义的变量：\(result.unresolved.joined(separator: ", "))", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.leading, 4)
            }
        }
    }
}
