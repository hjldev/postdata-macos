import PostDataKit
import SwiftUI

private enum CollectionSection: String, CaseIterable, Identifiable {
    case overview, variables, auth
    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "概览"
        case .variables: "变量"
        case .auth: "认证"
        }
    }
}

/// Collection name, description, variables and default auth. Changes are saved automatically.
struct CollectionSettingsView: View {
    @Environment(AppModel.self) private var model
    let collectionID: UUID
    @State private var section: CollectionSection = .overview

    var body: some View {
        if let collection = model.store.collection(id: collectionID) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "shippingbox")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    TextField("集合名称", text: binding(\.name, in: collection))
                        .textFieldStyle(.plain)
                        .font(.title2.bold())
                    Spacer()
                    Button {
                        model.newRequest(in: collectionID, folderID: nil)
                    } label: {
                        Label("新建请求", systemImage: "plus")
                    }
                    Button {
                        model.exportCollection(collectionID)
                    } label: {
                        Label("导出", systemImage: "square.and.arrow.up")
                    }
                }

                Picker("", selection: $section) {
                    ForEach(CollectionSection.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                switch section {
                case .overview:
                    overview(collection)
                case .variables:
                    VStack(alignment: .leading, spacing: 8) {
                        Text("集合变量只在本集合的请求中可用，优先级高于全局变量、低于环境变量。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        KeyValueEditor(items: binding(\.variables, in: collection), keyPlaceholder: "变量名", valuePlaceholder: "值", showsDescription: false)
                    }
                case .auth:
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("集合内认证方式为「Inherit auth from parent」的请求和文件夹会使用这里的设置。")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            AuthEditor(auth: binding(\.auth, in: collection), allowsInherit: false)
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ContentUnavailableView("集合已删除", systemImage: "trash")
        }
    }

    private func overview(_ collection: RequestCollection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 18) {
                stat("\(collection.requestCount)", "请求")
                stat("\(collection.destinations().count - 1)", "文件夹")
                stat("\(collection.variables.active.count)", "变量")
                stat(collection.auth.kind.title, "认证")
            }
            Text("描述").font(.callout.weight(.medium))
            TextEditor(text: binding(\.description, in: collection))
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.weight(.semibold))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<RequestCollection, Value>, in collection: RequestCollection) -> Binding<Value> {
        Binding(
            get: { model.store.collection(id: collectionID)?[keyPath: keyPath] ?? collection[keyPath: keyPath] },
            set: { newValue in model.store.updateCollection(collectionID) { $0[keyPath: keyPath] = newValue } }
        )
    }
}
