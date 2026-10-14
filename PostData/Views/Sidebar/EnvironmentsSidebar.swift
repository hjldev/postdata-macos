import PostDataKit
import SwiftUI

struct EnvironmentsSidebar: View {
    @Environment(AppModel.self) private var model
    let searchText: String

    var body: some View {
        List(selection: selection) {
            Section {
                environmentRow(model.store.globals, isGlobals: true)
            }
            Section("环境") {
                ForEach(filtered) { environment in
                    environmentRow(environment, isGlobals: false)
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if model.store.environments.isEmpty {
                ContentUnavailableView {
                    Label("还没有环境", systemImage: "square.stack.3d.up")
                } description: {
                    Text("环境用于在开发、测试、生产等配置之间切换变量，例如 {{baseUrl}}。")
                } actions: {
                    Button("新建环境") { model.newEnvironment() }
                }
                .padding(.top, 60)
            }
        }
    }

    private var filtered: [APIEnvironment] {
        guard !searchText.isEmpty else { return model.store.environments }
        return model.store.environments.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var selection: Binding<UUID?> {
        Binding(
            get: {
                if case .environment(let id) = model.tabs.selectedTab?.content { return id }
                return nil
            },
            set: { id in
                if let id { model.tabs.openEnvironment(id) }
            }
        )
    }

    private func environmentRow(_ environment: APIEnvironment, isGlobals: Bool) -> some View {
        let isActive = model.store.activeEnvironmentID == environment.id
        return HStack {
            Label(isGlobals ? "Globals" : environment.name, systemImage: isGlobals ? "globe" : "square.stack.3d.up")
                .lineLimit(1)
            Spacer()
            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .help("当前环境")
            }
            Text("\(environment.variables.active.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .tag(environment.id)
        .contextMenu {
            if !isGlobals {
                Button(isActive ? "取消激活" : "设为当前环境") {
                    model.store.activeEnvironmentID = isActive ? nil : environment.id
                }
                Divider()
                Button("重命名") { model.beginRename(.environment(environment.id), current: environment.name) }
                Button("复制") { model.store.duplicateEnvironment(id: environment.id) }
            }
            Button("导出…") { model.exportEnvironment(environment.id) }
            if !isGlobals {
                Divider()
                Button("删除", role: .destructive) { model.confirmDeleteEnvironment(environment) }
            }
        }
    }
}
