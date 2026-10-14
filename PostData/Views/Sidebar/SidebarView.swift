import PostDataKit
import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @State private var searchText = ""

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            Picker("", selection: $model.sidebarSection) {
                ForEach(SidebarSection.allCases) { section in
                    Label(section.title, systemImage: section.systemImage).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            switch model.sidebarSection {
            case .collections:
                CollectionsSidebar(searchText: searchText)
            case .environments:
                EnvironmentsSidebar(searchText: searchText)
            case .history:
                HistorySidebar(searchText: searchText)
            }

            Divider()
            footer
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "筛选")
    }

    private var footer: some View {
        HStack(spacing: 4) {
            switch model.sidebarSection {
            case .collections:
                Button { model.newCollection() } label: { Label("新建集合", systemImage: "plus") }
                Spacer()
                Button { model.activeSheet = .importData } label: { Label("导入", systemImage: "square.and.arrow.down") }
            case .environments:
                Button { model.newEnvironment() } label: { Label("新建环境", systemImage: "plus") }
                Spacer()
                Button { model.activeSheet = .importData } label: { Label("导入", systemImage: "square.and.arrow.down") }
            case .history:
                Text("\(model.store.history.count) 条记录")
                    .foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive) { model.confirmClearHistory() } label: { Label("清空", systemImage: "trash") }
                    .disabled(model.store.history.isEmpty)
            }
        }
        .buttonStyle(.borderless)
        .labelStyle(.titleAndIcon)
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
