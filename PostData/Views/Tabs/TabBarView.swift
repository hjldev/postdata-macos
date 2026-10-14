import PostDataKit
import SwiftUI

struct TabBarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(model.tabs.tabs) { tab in
                            TabItemView(tab: tab, isSelected: tab.id == model.tabs.selectedTabID)
                                .id(tab.id)
                            Divider().frame(height: 18)
                        }
                    }
                }
                .onChange(of: model.tabs.selectedTabID) { _, id in
                    if let id { withAnimation { proxy.scrollTo(id) } }
                }
            }
            Button {
                model.tabs.newRequest()
            } label: {
                Image(systemName: "plus")
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("新建请求 (⌘T)")
            Spacer(minLength: 0)
        }
        .frame(height: 36)
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.5))
    }
}

private struct TabItemView: View {
    @Environment(AppModel.self) private var model
    let tab: EditorTab
    let isSelected: Bool
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            icon
            Text(title)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(isSelected ? .primary : .secondary)
            closeButton
        }
        .font(.callout)
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(minWidth: 110, maxWidth: 220, maxHeight: .infinity)
        .background(isSelected ? Color(nsColor: .textBackgroundColor) : (isHovering ? Color.primary.opacity(0.04) : .clear))
        .overlay(alignment: .top) {
            if isSelected {
                Rectangle().fill(Color.accentColor).frame(height: 2)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { model.tabs.selectedTabID = tab.id }
        .contextMenu {
            Button("关闭标签") { model.requestClose(tab.id) }
            Button("关闭其他标签") { model.tabs.closeOthers(tab.id) }
            if let state = tab.requestState {
                Divider()
                Button("复制为新请求") {
                    model.tabs.openRequest(state.draft.withNewID(name: state.draft.name + " Copy"), collectionID: nil)
                }
            }
        }
        .help(title)
    }

    @ViewBuilder
    private var icon: some View {
        switch tab.content {
        case .request(let state):
            MethodLabel(method: state.draft.method)
                .frame(width: nil)
                .fixedSize()
        case .environment(let id):
            Image(systemName: model.store.isGlobals(id) ? "globe" : "square.stack.3d.up")
                .foregroundStyle(.secondary)
        case .collection:
            Image(systemName: "shippingbox")
                .foregroundStyle(.secondary)
        }
    }

    private var title: String {
        switch tab.content {
        case .request(let state):
            state.draft.name
        case .environment(let id):
            model.store.isGlobals(id) ? "Globals" : (model.store.environment(id: id)?.name ?? "环境")
        case .collection(let id):
            model.store.collection(id: id)?.name ?? "集合"
        }
    }

    private var isDirty: Bool { tab.requestState?.isDirty == true }

    @ViewBuilder
    private var closeButton: some View {
        ZStack {
            if isDirty && !isHovering {
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 7, height: 7)
            } else {
                Button {
                    model.requestClose(tab.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .opacity(isHovering || isSelected ? 1 : 0)
                .help("关闭标签")
            }
        }
        .frame(width: 16, height: 16)
    }
}
