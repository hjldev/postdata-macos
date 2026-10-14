import PostDataKit
import SwiftUI

/// Choose a name and a collection/folder for an unsaved request (or "Save As" for a saved one).
struct SaveRequestSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let state: RequestTabState

    @State private var name = ""
    @State private var selection: String?
    @State private var newCollectionName = ""
    @State private var isCreatingCollection = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(state.collectionID == nil ? "保存请求" : "另存为").font(.title2.bold())

            TextField("请求名称", text: $name)
                .textFieldStyle(.roundedBorder)

            Text("保存到：").font(.callout.weight(.medium))
            List(selection: $selection) {
                ForEach(destinations) { destination in
                    Label {
                        Text(destination.path.components(separatedBy: " / ").last ?? destination.path)
                    } icon: {
                        Image(systemName: destination.folderID == nil ? "shippingbox" : "folder")
                    }
                    .padding(.leading, CGFloat(destination.depth) * 16)
                    .tag(destination.id)
                }
            }
            .listStyle(.bordered)
            .alternatingRowBackgrounds()
            .frame(height: 220)
            .overlay {
                if destinations.isEmpty {
                    Text("还没有集合，请先新建一个。").foregroundStyle(.secondary)
                }
            }

            HStack {
                if isCreatingCollection {
                    TextField("新集合名称", text: $newCollectionName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(createCollection)
                    Button("创建", action: createCollection)
                        .disabled(newCollectionName.trimmingCharacters(in: .whitespaces).isEmpty)
                } else {
                    Button {
                        isCreatingCollection = true
                    } label: {
                        Label("新建集合", systemImage: "plus")
                    }
                }
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedDestination == nil || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear {
            name = state.draft.name
            if let collectionID = state.collectionID {
                let parent = model.store.collection(id: collectionID)?.parentFolderID(of: state.draft.id)
                selection = destinations.first { $0.collectionID == collectionID && $0.folderID == parent }?.id
            } else {
                selection = destinations.first?.id
            }
        }
    }

    private var destinations: [CollectionDestination] { model.store.allDestinations }

    private var selectedDestination: CollectionDestination? {
        destinations.first { $0.id == selection }
    }

    private func createCollection() {
        let trimmed = newCollectionName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let collection = model.store.addCollection(name: trimmed)
        selection = CollectionDestination(collectionID: collection.id, folderID: nil, path: collection.name, depth: 0).id
        newCollectionName = ""
        isCreatingCollection = false
    }

    private func save() {
        guard let destination = selectedDestination else { return }
        model.save(state, name: name.trimmingCharacters(in: .whitespaces), to: destination)
        dismiss()
    }
}
