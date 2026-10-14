import PostDataKit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 230, ideal: 280, max: 440)
        } detail: {
            WorkspaceView()
        }
        .navigationTitle(windowTitle)
        .navigationSubtitle(windowSubtitle)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Menu {
                    Button("新建请求") { model.tabs.newRequest() }
                    Button("新建集合") { model.newCollection() }
                    Button("新建环境") { model.newEnvironment() }
                } label: {
                    Label("新建", systemImage: "plus")
                }
                .help("新建")
            }
            ToolbarItem(placement: .primaryAction) {
                EnvironmentPicker()
            }
            ToolbarItem(placement: .primaryAction) {
                VariablesQuickLook()
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.activeSheet = .importData
                } label: {
                    Label("导入", systemImage: "square.and.arrow.down")
                }
                .help("导入 Postman 集合、环境或 cURL (⌘O)")
            }
        }
        .sheet(item: $model.activeSheet) { sheet in
            switch sheet {
            case .importData:
                ImportSheet()
            case .codeSnippet(let state):
                CodeSnippetSheet(state: state)
            case .saveRequest(let state):
                SaveRequestSheet(state: state)
            }
        }
        .alert(
            model.renameRequest?.title ?? "重命名",
            isPresented: Binding(get: { model.renameRequest != nil }, set: { if !$0 { model.renameRequest = nil } })
        ) {
            TextField("名称", text: $model.renameText)
            Button("确定") { model.commitRename() }
            Button("取消", role: .cancel) { model.renameRequest = nil }
        }
        .confirmationDialog(
            model.deleteRequest?.title ?? "",
            isPresented: Binding(get: { model.deleteRequest != nil }, set: { if !$0 { model.deleteRequest = nil } }),
            titleVisibility: .visible,
            presenting: model.deleteRequest
        ) { _ in
            Button("删除", role: .destructive) { model.performDelete() }
            Button("取消", role: .cancel) { model.deleteRequest = nil }
        } message: { request in
            Text(request.message)
        }
        .confirmationDialog(
            "是否保存对「\(pendingCloseTitle)」的修改？",
            isPresented: Binding(get: { model.pendingCloseTabID != nil }, set: { if !$0 { model.pendingCloseTabID = nil } }),
            titleVisibility: .visible
        ) {
            Button("保存") { model.resolvePendingClose(save: true) }
            Button("不保存", role: .destructive) { model.resolvePendingClose(save: false) }
            Button("取消", role: .cancel) { model.pendingCloseTabID = nil }
        } message: {
            Text("如果不保存，所做的修改将会丢失。")
        }
        .alert(
            "出错了",
            isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button("好") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var pendingCloseTitle: String {
        model.pendingCloseTabID.flatMap { model.tabs.tab(id: $0)?.requestState?.draft.name } ?? ""
    }

    private var windowTitle: String {
        model.tabs.selectedRequest?.draft.name ?? "PostData"
    }

    private var windowSubtitle: String {
        guard let state = model.tabs.selectedRequest else { return "" }
        return model.store.collection(id: state.collectionID)?.name ?? "未保存"
    }
}

/// The detail column: tab bar plus the selected tab's editor.
struct WorkspaceView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            if !model.tabs.tabs.isEmpty {
                TabBarView()
                Divider()
            }
            if let tab = model.tabs.selectedTab {
                switch tab.content {
                case .request(let state):
                    RequestWorkspaceView(state: state)
                        .id(tab.id)
                case .environment(let id):
                    EnvironmentEditorView(environmentID: id)
                        .id(tab.id)
                case .collection(let id):
                    CollectionSettingsView(collectionID: id)
                        .id(tab.id)
                }
            } else {
                WelcomeView()
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .background(CloseTabShortcut())
    }
}

/// ⌘W closes the current tab while tabs are open; with no tabs it falls through to closing the window.
private struct CloseTabShortcut: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button("关闭标签") { model.closeSelectedTab() }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(model.tabs.selectedTab == nil)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }
}

private struct WelcomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ContentUnavailableView {
            Label("PostData", systemImage: "paperplane.circle")
        } description: {
            Text("原生 macOS API 调试工具。新建一个请求，或从 Postman / cURL 导入。")
        } actions: {
            Button("新建请求") { model.tabs.newRequest() }
                .buttonStyle(.borderedProminent)
            Button("导入…") { model.activeSheet = .importData }
        }
    }
}

/// Toolbar menu for choosing the active environment.
private struct EnvironmentPicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            Button {
                model.store.activeEnvironmentID = nil
            } label: {
                if model.store.activeEnvironmentID == nil {
                    Label("无环境", systemImage: "checkmark")
                } else {
                    Text("无环境")
                }
            }
            if !model.store.environments.isEmpty { Divider() }
            ForEach(model.store.environments) { environment in
                Button {
                    model.store.activeEnvironmentID = environment.id
                } label: {
                    if model.store.activeEnvironmentID == environment.id {
                        Label(environment.name, systemImage: "checkmark")
                    } else {
                        Text(environment.name)
                    }
                }
            }
            Divider()
            Button("管理环境…") { model.sidebarSection = .environments }
        } label: {
            Label(model.store.activeEnvironment?.name ?? "无环境", systemImage: "square.stack.3d.up")
                .labelStyle(.titleAndIcon)
        }
        .help("当前环境")
    }
}

/// A popover listing the variables currently in scope.
private struct VariablesQuickLook: View {
    @Environment(AppModel.self) private var model
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Label("变量", systemImage: "eye")
        }
        .help("查看当前生效的变量")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                section(
                    title: model.store.activeEnvironment.map { "环境：\($0.name)" } ?? "环境：无",
                    variables: model.store.activeEnvironment?.variables ?? [],
                    edit: model.store.activeEnvironment.map { environment in { model.tabs.openEnvironment(environment.id) } }
                )
                Divider()
                section(
                    title: "Globals",
                    variables: model.store.globals.variables,
                    edit: { model.tabs.openEnvironment(model.store.globals.id) }
                )
            }
            .padding(14)
            .frame(width: 380)
        }
    }

    private func section(title: String, variables: [KeyValue], edit: (() -> Void)?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                if let edit {
                    Button("编辑") {
                        isPresented = false
                        edit()
                    }
                    .buttonStyle(.link)
                }
            }
            let active = variables.active
            if active.isEmpty {
                Text("没有变量").foregroundStyle(.secondary).font(.callout)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    ForEach(active) { variable in
                        GridRow {
                            Text(variable.key).fontWeight(.medium)
                            Text(variable.value).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                    }
                }
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
            }
        }
    }
}
