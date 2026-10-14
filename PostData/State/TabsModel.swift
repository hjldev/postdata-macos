import Foundation
import Observation
import PostDataKit

struct EditorTab: Identifiable {
    enum Content {
        case request(RequestTabState)
        case environment(UUID)
        case collection(UUID)
    }

    let id: UUID
    let content: Content

    var requestState: RequestTabState? {
        if case .request(let state) = content { return state }
        return nil
    }
}

/// The open tabs and which one is selected.
@Observable
final class TabsModel {
    private(set) var tabs: [EditorTab] = []
    var selectedTabID: UUID? {
        didSet {
            // Background tabs keep only raw response bytes; the text is rebuilt when they're shown again.
            if oldValue != selectedTabID, let oldValue {
                tab(id: oldValue)?.requestState?.releaseDisplayContent()
            }
        }
    }

    var selectedTab: EditorTab? { tabs.first { $0.id == selectedTabID } }
    var selectedRequest: RequestTabState? { selectedTab?.requestState }
    var selectedIndex: Int? { tabs.firstIndex { $0.id == selectedTabID } }

    func tab(id: UUID) -> EditorTab? { tabs.first { $0.id == id } }

    /// The tab editing a saved request, if open.
    func requestTab(forItem itemID: UUID) -> RequestTabState? {
        tabs.lazy.compactMap(\.requestState).first { $0.draft.id == itemID && $0.collectionID != nil }
    }

    /// Opens a request, reusing the tab if this saved request is already open.
    @discardableResult
    func openRequest(_ request: HTTPRequest, collectionID: UUID?, baseline: HTTPRequest? = nil) -> RequestTabState {
        if collectionID != nil,
           let existing = tabs.first(where: { $0.requestState?.draft.id == request.id && $0.requestState?.collectionID == collectionID }) {
            selectedTabID = existing.id
            return existing.requestState!
        }
        let state = RequestTabState(request: request, collectionID: collectionID, baseline: baseline)
        append(EditorTab(id: state.id, content: .request(state)))
        return state
    }

    @discardableResult
    func newRequest() -> RequestTabState {
        openRequest(HTTPRequest(settings: AppSettings.defaultRequestSettings), collectionID: nil)
    }

    func openEnvironment(_ id: UUID) {
        if let existing = tabs.first(where: { if case .environment(id) = $0.content { true } else { false } }) {
            selectedTabID = existing.id
        } else {
            append(EditorTab(id: UUID(), content: .environment(id)))
        }
    }

    func openCollection(_ id: UUID) {
        if let existing = tabs.first(where: { if case .collection(id) = $0.content { true } else { false } }) {
            selectedTabID = existing.id
        } else {
            append(EditorTab(id: UUID(), content: .collection(id)))
        }
    }

    func close(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].requestState?.cancel()
        tabs.remove(at: index)
        if selectedTabID == id {
            selectedTabID = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)].id
        }
    }

    func closeOthers(_ id: UUID) {
        for tab in tabs where tab.id != id { tab.requestState?.cancel() }
        tabs.removeAll { $0.id != id }
        selectedTabID = tabs.first?.id
    }

    func selectNext() { selectOffset(1) }
    func selectPrevious() { selectOffset(-1) }

    private func selectOffset(_ offset: Int) {
        guard !tabs.isEmpty else { return }
        let current = selectedIndex ?? 0
        selectedTabID = tabs[(current + offset + tabs.count) % tabs.count].id
    }

    private func append(_ tab: EditorTab) {
        if let index = selectedIndex {
            tabs.insert(tab, at: index + 1)
        } else {
            tabs.append(tab)
        }
        selectedTabID = tab.id
    }

    /// Fixes tabs after deletions: closes tabs whose target is gone and detaches orphaned requests.
    func reconcile(with store: AppStore) {
        var closing: [UUID] = []
        for tab in tabs {
            switch tab.content {
            case .request(let state):
                if let collectionID = state.collectionID,
                   store.collection(id: collectionID)?.contains(itemID: state.draft.id) != true {
                    // Keep the work but mark it unsaved so closing asks before discarding it.
                    state.collectionID = nil
                    state.baseline = HTTPRequest(id: state.draft.id)
                }
            case .environment(let id):
                if store.environment(id: id) == nil { closing.append(tab.id) }
            case .collection(let id):
                if store.collection(id: id) == nil { closing.append(tab.id) }
            }
        }
        closing.forEach(close)
    }

    /// Updates which collection open tabs point to after requests moved between collections.
    func retarget(requestIDs: Set<UUID>, to collectionID: UUID) {
        for state in tabs.compactMap(\.requestState) where requestIDs.contains(state.draft.id) && state.collectionID != nil {
            state.collectionID = collectionID
        }
    }

    func restore(_ restored: [EditorTab], selectedIndex: Int?) {
        tabs = restored
        if let selectedIndex, restored.indices.contains(selectedIndex) {
            selectedTabID = restored[selectedIndex].id
        } else {
            selectedTabID = restored.first?.id
        }
    }
}
