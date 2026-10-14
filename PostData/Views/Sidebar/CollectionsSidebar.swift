import PostDataKit
import SwiftUI

struct CollectionsSidebar: View {
    @Environment(AppModel.self) private var model
    let searchText: String

    var body: some View {
        List(selection: selection) {
            if searchText.isEmpty {
                ForEach(model.store.collections) { collection in
                    DisclosureGroup(isExpanded: expansion(collection.id)) {
                        CollectionItemRows(items: collection.items, collectionID: collection.id)
                    } label: {
                        Label {
                            Text(collection.name).lineLimit(1)
                        } icon: {
                            Image(systemName: "shippingbox")
                        }
                        .contextMenu { CollectionMenu(collection: collection) }
                    }
                    .tag(collection.id)
                }
            } else {
                ForEach(searchResults, id: \.request.id) { result in
                    VStack(alignment: .leading, spacing: 2) {
                        RequestRowLabel(request: result.request)
                        Text(result.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .tag(result.request.id)
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if model.store.collections.isEmpty {
                ContentUnavailableView {
                    Label("还没有集合", systemImage: "shippingbox")
                } description: {
                    Text("集合用于整理和保存请求。")
                } actions: {
                    Button("新建集合") { model.newCollection() }
                    Button("导入 Postman 集合…") { model.activeSheet = .importData }
                }
            } else if !searchText.isEmpty, searchResults.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }

    /// Selection mirrors the open request; picking a row opens it.
    private var selection: Binding<UUID?> {
        Binding(
            get: {
                guard let state = model.tabs.selectedRequest, state.collectionID != nil else { return nil }
                return state.draft.id
            },
            set: { id in
                if let id { model.openItem(id) }
            }
        )
    }

    private func expansion(_ id: UUID) -> Binding<Bool> {
        Binding(get: { model.isExpanded(id) }, set: { model.setExpanded(id, $0) })
    }

    private struct SearchResult {
        let request: HTTPRequest
        let path: String
    }

    private var searchResults: [SearchResult] {
        let query = searchText.lowercased()
        return model.store.collections.flatMap { collection in
            collection.allRequests
                .filter { $0.name.lowercased().contains(query) || $0.url.lowercased().contains(query) }
                .map { request in
                    let folders = collection.ancestors(of: request.id)?.map(\.name) ?? []
                    return SearchResult(request: request, path: ([collection.name] + folders).joined(separator: " / "))
                }
        }
    }
}

/// Folders and requests of one level, recursing into folders.
private struct CollectionItemRows: View {
    @Environment(AppModel.self) private var model
    let items: [CollectionItem]
    let collectionID: UUID

    var body: some View {
        ForEach(items) { item in
            switch item {
            case .folder(let folder):
                DisclosureGroup(isExpanded: Binding(get: { model.isExpanded(folder.id) }, set: { model.setExpanded(folder.id, $0) })) {
                    CollectionItemRows(items: folder.items, collectionID: collectionID)
                } label: {
                    Label {
                        Text(folder.name).lineLimit(1)
                    } icon: {
                        Image(systemName: "folder")
                    }
                    .contextMenu { ItemMenu(item: item, collectionID: collectionID) }
                }
                .tag(folder.id)
            case .request(let request):
                RequestRowLabel(request: request, isDirty: model.tabs.requestTab(forItem: request.id)?.isDirty == true)
                    .tag(request.id)
                    .contextMenu { ItemMenu(item: item, collectionID: collectionID) }
            }
        }
    }
}

struct RequestRowLabel: View {
    let request: HTTPRequest
    var isDirty = false

    var body: some View {
        HStack(spacing: 6) {
            MethodLabel(method: request.method)
            Text(request.name)
                .lineLimit(1)
                .truncationMode(.tail)
            if isDirty {
                Circle().fill(Color.secondary).frame(width: 6, height: 6)
                    .help("有未保存的修改")
            }
        }
        .help(request.url)
    }
}

private struct CollectionMenu: View {
    @Environment(AppModel.self) private var model
    let collection: RequestCollection

    var body: some View {
        Button("新建请求") { model.newRequest(in: collection.id, folderID: nil) }
        Button("新建文件夹") { model.newFolder(in: collection.id, parentID: nil) }
        Divider()
        Button("集合设置…") { model.tabs.openCollection(collection.id) }
        Button("重命名") { model.beginRename(.collection(collection.id), current: collection.name) }
        Button("复制集合") { model.store.duplicateCollection(id: collection.id) }
        Button("导出为 Postman v2.1…") { model.exportCollection(collection.id) }
        Divider()
        Button("删除", role: .destructive) { model.confirmDeleteCollection(collection) }
    }
}

private struct ItemMenu: View {
    @Environment(AppModel.self) private var model
    let item: CollectionItem
    let collectionID: UUID

    var body: some View {
        if let folder = item.folder {
            Button("新建请求") { model.newRequest(in: collectionID, folderID: folder.id) }
            Button("新建文件夹") { model.newFolder(in: collectionID, parentID: folder.id) }
            Divider()
        } else if let request = item.request {
            Button("打开") { model.tabs.openRequest(request, collectionID: collectionID) }
            Button("在新标签中打开副本") { model.tabs.openRequest(request.withNewID(name: request.name + " Copy"), collectionID: nil) }
            Divider()
        }
        Button("重命名") { model.beginRename(.item(collectionID: collectionID, itemID: item.id), current: item.name) }
        Button("复制") { model.duplicateItem(item.id, in: collectionID) }
        Menu("移动到") {
            ForEach(model.moveDestinations(for: item.id, in: collectionID)) { destination in
                Button(destination.path) {
                    model.move(item.id, from: collectionID, to: destination)
                }
            }
        }
        Divider()
        Button("删除", role: .destructive) { model.confirmDeleteItem(item, in: collectionID) }
    }
}
