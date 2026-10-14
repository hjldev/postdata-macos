import PostDataKit
import SwiftUI

/// A request tab: editor on top, response below, separated by a draggable divider.
struct RequestWorkspaceView: View {
    let state: RequestTabState

    var body: some View {
        VSplitView {
            RequestEditorView(state: state)
                .frame(minHeight: 220, idealHeight: 340)
            ResponseView(state: state)
                .frame(minHeight: 160, idealHeight: 420)
        }
    }
}

struct RequestEditorView: View {
    @Environment(AppModel.self) private var model
    @Bindable var state: RequestTabState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RequestHeaderView(state: state)
            URLBarView(state: state)
            Picker("", selection: $state.section) {
                ForEach(RequestSection.allCases) { section in
                    Text(title(for: section)).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Group {
                switch state.section {
                case .params:
                    KeyValueEditor(
                        items: Binding(get: { state.draft.queryParams }, set: { state.draft.setQueryParams($0) }),
                        keyPlaceholder: "Key",
                        valuePlaceholder: "Value"
                    )
                case .auth:
                    ScrollView {
                        AuthEditor(
                            auth: $state.draft.auth,
                            allowsInherit: true,
                            inheritedDescription: model.store.inheritedAuthDescription(for: state.draft, collectionID: state.collectionID)
                        )
                    }
                case .headers:
                    VStack(alignment: .leading, spacing: 6) {
                        KeyValueEditor(items: $state.draft.headers, keyPlaceholder: "Key", valuePlaceholder: "Value")
                        Text("User-Agent、Accept、Content-Type 及认证头会在未手动设置时自动添加。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                case .body:
                    BodyEditor(requestBody: $state.draft.body, method: state.draft.method)
                case .settings:
                    ScrollView {
                        RequestSettingsView(settings: $state.draft.settings)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private func title(for section: RequestSection) -> String {
        let count: Int = switch section {
        case .params: state.draft.queryParams.active.count
        case .headers: state.draft.headers.active.count
        default: 0
        }
        var title = section.title
        if count > 0 { title += " (\(count))" }
        if section == .body, state.draft.body.mode != .none { title += " •" }
        if section == .auth, state.draft.auth.kind != .inherit, state.draft.auth.kind != .none { title += " •" }
        return title
    }
}

/// Breadcrumb (collection / folders) and the editable request name.
private struct RequestHeaderView: View {
    @Environment(AppModel.self) private var model
    @Bindable var state: RequestTabState
    @State private var isEditingName = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            if let path = breadcrumb {
                Text(path)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Image(systemName: "doc.badge.ellipsis")
                    .foregroundStyle(.secondary)
                    .help("未保存到集合")
            }
            if isEditingName {
                TextField("请求名称", text: $state.draft.name)
                    .textFieldStyle(.plain)
                    .font(.headline)
                    .focused($nameFocused)
                    .onSubmit { isEditingName = false }
                    .onChange(of: nameFocused) { _, focused in
                        if !focused { isEditingName = false }
                    }
            } else {
                // Shown as text so the name field doesn't grab initial focus; click to rename.
                Text(state.draft.name.isEmpty ? "未命名请求" : state.draft.name)
                    .font(.headline)
                    .lineLimit(1)
                    .onTapGesture {
                        isEditingName = true
                        nameFocused = true
                    }
                    .help("点击重命名")
            }
            Spacer()
            Button {
                model.activeSheet = .codeSnippet(state)
            } label: {
                Label("代码", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            .help("生成代码片段 (⇧⌘C)")
        }
    }

    private var breadcrumb: String? {
        guard let collection = model.store.collection(id: state.collectionID) else { return nil }
        let folders = collection.ancestors(of: state.draft.id)?.map(\.name) ?? []
        return ([collection.name] + folders).joined(separator: " / ")
    }
}
