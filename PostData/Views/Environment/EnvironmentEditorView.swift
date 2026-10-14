import PostDataKit
import SwiftUI

/// Edits an environment's (or the globals') variables. Changes are saved automatically.
struct EnvironmentEditorView: View {
    @Environment(AppModel.self) private var model
    let environmentID: UUID

    var body: some View {
        if let environment = model.store.environment(id: environmentID) {
            let isGlobals = model.store.isGlobals(environmentID)
            let isActive = model.store.activeEnvironmentID == environmentID
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: isGlobals ? "globe" : "square.stack.3d.up")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    if isGlobals {
                        Text("Globals").font(.title2.bold())
                    } else {
                        TextField("环境名称", text: Binding(
                            get: { environment.name },
                            set: { newName in model.store.updateEnvironment(environmentID) { $0.name = newName } }
                        ))
                        .textFieldStyle(.plain)
                        .font(.title2.bold())
                    }
                    Spacer()
                    if !isGlobals {
                        if isActive {
                            Label("当前环境", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Button("设为当前环境") { model.store.activeEnvironmentID = environmentID }
                        }
                    }
                    Menu {
                        Button("导出…") { model.exportEnvironment(environmentID) }
                        if !isGlobals {
                            Button("复制") { model.store.duplicateEnvironment(id: environmentID) }
                            Divider()
                            Button("删除", role: .destructive) { model.confirmDeleteEnvironment(environment) }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuIndicator(.hidden)
                    .fixedSize()
                }

                Text(isGlobals
                     ? "全局变量在所有请求中可用，优先级最低，会被集合变量和环境变量覆盖。"
                     : "在 URL、Header、Body、认证等处用 {{变量名}} 引用。环境变量优先级最高。")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                KeyValueEditor(
                    items: Binding(
                        get: { environment.variables },
                        set: { variables in model.store.updateEnvironment(environmentID) { $0.variables = variables } }
                    ),
                    keyPlaceholder: "变量名",
                    valuePlaceholder: "值",
                    showsDescription: false
                )
            }
            .padding(20)
        } else {
            ContentUnavailableView("环境已删除", systemImage: "trash")
        }
    }
}
