import AppKit
import Foundation
import Observation
import PostDataKit
import UniformTypeIdentifiers

enum SidebarSection: String, CaseIterable, Identifiable {
    case collections, environments, history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .collections: "集合"
        case .environments: "环境"
        case .history: "历史"
        }
    }

    var systemImage: String {
        switch self {
        case .collections: "folder"
        case .environments: "square.stack.3d.up"
        case .history: "clock.arrow.circlepath"
        }
    }
}

enum ActiveSheet: Identifiable {
    case importData
    case codeSnippet(RequestTabState)
    case saveRequest(RequestTabState)

    var id: String {
        switch self {
        case .importData: "import"
        case .codeSnippet(let state): "code-\(state.id)"
        case .saveRequest(let state): "save-\(state.id)"
        }
    }
}

struct RenameRequest: Identifiable {
    enum Target {
        case collection(UUID)
        case item(collectionID: UUID, itemID: UUID)
        case environment(UUID)
    }

    let id = UUID()
    let target: Target
    let title: String
}

struct DeleteRequest: Identifiable {
    enum Target {
        case collection(UUID)
        case item(collectionID: UUID, itemID: UUID)
        case environment(UUID)
        case history
    }

    let id = UUID()
    let target: Target
    let title: String
    let message: String
}

enum ImportOutcome {
    case collection(name: String, requestCount: Int, warnings: [String])
    case environment(name: String, variableCount: Int)
    case curl
}

/// App-wide state and the actions views and menu commands invoke.
@Observable
final class AppModel {
    let store: AppStore
    let tabs = TabsModel()

    var sidebarSection: SidebarSection = .collections
    var expandedItemIDs = Set<UUID>()
    var activeSheet: ActiveSheet?
    var renameRequest: RenameRequest?
    var renameText = ""
    var deleteRequest: DeleteRequest?
    /// A dirty tab the user asked to close; drives the "save changes?" dialog.
    var pendingCloseTabID: UUID?
    var errorMessage: String?

    init(storage: WorkspaceStorage = WorkspaceStorage(rootURL: AppSettings.dataDirectory)) {
        AppSettings.registerDefaults()
        store = AppStore(storage: storage)
        restoreSession()
        #if DEBUG
        applyDebugLaunchOptions()
        #endif
    }

    // MARK: Sending

    func send(_ tab: RequestTabState) {
        tab.cancel()
        let request = tab.draft
        let resolved: ResolvedRequest
        do {
            resolved = try resolve(tab)
        } catch {
            tab.response = .failed(error.localizedDescription)
            return
        }
        tab.response = .loading(startedAt: Date())
        let client = store.client
        tab.sendTask = Task { [weak self, weak tab] in
            do {
                let response = try await client.send(resolved)
                let content = await Self.interpret(response)
                guard !Task.isCancelled, let tab else { return }
                tab.response = .loaded(LoadedResponse(response: response, content: content, receivedAt: Date()))
                self?.store.addHistory(HistoryEntry(
                    request: request,
                    statusCode: response.statusCode,
                    duration: response.duration,
                    size: response.bodySize
                ))
            } catch {
                guard let tab else { return }
                if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                    tab.response = .cancelled
                    return
                }
                tab.response = .failed(error.localizedDescription)
                self?.store.addHistory(HistoryEntry(request: request, errorMessage: error.localizedDescription))
            }
        }
    }

    func sendSelected() {
        if let tab = tabs.selectedRequest { send(tab) }
    }

    func resolve(_ tab: RequestTabState) throws -> ResolvedRequest {
        try RequestBuilder.resolve(
            tab.draft,
            auth: store.effectiveAuth(for: tab.draft, collectionID: tab.collectionID),
            variables: store.variableResolver(collectionID: tab.collectionID)
        )
    }

    /// Decoding and pretty-printing large bodies happens off the main thread.
    @concurrent
    nonisolated static func interpret(_ response: HTTPResponse) async -> ResponseContent {
        ResponseContent.make(from: response)
    }

    // MARK: Saving requests

    func save(_ tab: RequestTabState) {
        if let collectionID = tab.collectionID, store.updateRequest(tab.draft, in: collectionID) {
            tab.baseline = tab.draft
        } else {
            activeSheet = .saveRequest(tab)
        }
    }

    func saveSelected() {
        if let tab = tabs.selectedRequest { save(tab) }
    }

    func saveSelectedAs() {
        if let tab = tabs.selectedRequest { activeSheet = .saveRequest(tab) }
    }

    /// "Save" for unsaved tabs and "Save As" for saved ones (which creates a copy).
    func save(_ tab: RequestTabState, name: String, to destination: CollectionDestination) {
        var request = tab.draft
        request.name = name
        if tab.collectionID != nil { request = request.withNewID() }
        guard store.insert(.request(request), into: destination) else {
            errorMessage = "保存失败：目标集合或文件夹已不存在。"
            return
        }
        tab.draft = request
        tab.baseline = request
        tab.collectionID = destination.collectionID
        expand(destination)
    }

    // MARK: Tabs

    func requestClose(_ tabID: UUID) {
        guard let tab = tabs.tab(id: tabID) else { return }
        if let state = tab.requestState, state.isDirty {
            tabs.selectedTabID = tabID
            pendingCloseTabID = tabID
        } else {
            tabs.close(tabID)
        }
    }

    func closeSelectedTab() {
        if let id = tabs.selectedTabID { requestClose(id) }
    }

    func resolvePendingClose(save shouldSave: Bool) {
        guard let id = pendingCloseTabID, let tab = tabs.tab(id: id) else {
            pendingCloseTabID = nil
            return
        }
        pendingCloseTabID = nil
        guard shouldSave, let state = tab.requestState else {
            tabs.close(id)
            return
        }
        if let collectionID = state.collectionID, store.updateRequest(state.draft, in: collectionID) {
            tabs.close(id)
        } else {
            // Needs a destination first; the tab stays open after saving.
            activeSheet = .saveRequest(state)
        }
    }

    // MARK: Sidebar actions

    func openItem(_ id: UUID) {
        switch store.locate(id) {
        case .collection(let collection):
            tabs.openCollection(collection.id)
        case .folder(_, let folder):
            toggleExpanded(folder.id)
        case .request(let collectionID, let request):
            tabs.openRequest(request, collectionID: collectionID)
        case nil:
            break
        }
    }

    func newCollection() {
        let collection = store.addCollection(name: "New Collection")
        sidebarSection = .collections
        expandedItemIDs.insert(collection.id)
        beginRename(.collection(collection.id), current: collection.name)
    }

    func newRequest(in collectionID: UUID, folderID: UUID?) {
        let request = HTTPRequest(name: "New Request", settings: AppSettings.defaultRequestSettings)
        let destination = CollectionDestination(collectionID: collectionID, folderID: folderID, path: "", depth: 0)
        guard store.insert(.request(request), into: destination) else { return }
        expand(destination)
        tabs.openRequest(request, collectionID: collectionID)
    }

    func newFolder(in collectionID: UUID, parentID: UUID?) {
        let folder = Folder(name: "New Folder")
        let destination = CollectionDestination(collectionID: collectionID, folderID: parentID, path: "", depth: 0)
        guard store.insert(.folder(folder), into: destination) else { return }
        expand(destination)
        beginRename(.item(collectionID: collectionID, itemID: folder.id), current: folder.name)
    }

    func newEnvironment() {
        let environment = store.addEnvironment(name: "New Environment")
        sidebarSection = .environments
        tabs.openEnvironment(environment.id)
    }

    func duplicateItem(_ itemID: UUID, in collectionID: UUID) {
        store.updateCollection(collectionID) { $0.duplicate(itemID: itemID) }
    }

    /// Valid "Move to…" targets: anywhere except the item itself, its descendants and its current parent.
    func moveDestinations(for itemID: UUID, in collectionID: UUID) -> [CollectionDestination] {
        guard let collection = store.collection(id: collectionID) else { return [] }
        var excluded = Set<UUID>([itemID])
        if let folder = collection.item(withID: itemID)?.folder {
            RequestCollection.walk(folder.items) { if let folder = $0.folder { excluded.insert(folder.id) } }
        }
        let currentParent = collection.parentFolderID(of: itemID)
        return store.allDestinations.filter { destination in
            if destination.collectionID == collectionID {
                if destination.folderID == currentParent { return false }
                if let folderID = destination.folderID, excluded.contains(folderID) { return false }
            }
            return true
        }
    }

    func move(_ itemID: UUID, from collectionID: UUID, to destination: CollectionDestination) {
        if destination.collectionID == collectionID {
            store.updateCollection(collectionID) { $0.move(itemID: itemID, toFolder: destination.folderID) }
        } else {
            var removed: CollectionItem?
            store.updateCollection(collectionID) { removed = $0.remove(itemID: itemID) }
            guard let removed else { return }
            store.insert(removed, into: destination)
            var requestIDs = Set<UUID>()
            if let request = removed.request { requestIDs.insert(request.id) }
            if let folder = removed.folder {
                RequestCollection.walk(folder.items) { if let request = $0.request { requestIDs.insert(request.id) } }
            }
            tabs.retarget(requestIDs: requestIDs, to: destination.collectionID)
        }
        expand(destination)
    }

    func isExpanded(_ id: UUID) -> Bool {
        expandedItemIDs.contains(id)
    }

    func setExpanded(_ id: UUID, _ expanded: Bool) {
        if expanded { expandedItemIDs.insert(id) } else { expandedItemIDs.remove(id) }
    }

    func toggleExpanded(_ id: UUID) {
        setExpanded(id, !expandedItemIDs.contains(id))
    }

    private func expand(_ destination: CollectionDestination) {
        expandedItemIDs.insert(destination.collectionID)
        if let folderID = destination.folderID {
            expandedItemIDs.insert(folderID)
            for folder in store.collection(id: destination.collectionID)?.ancestors(of: folderID) ?? [] {
                expandedItemIDs.insert(folder.id)
            }
        }
    }

    // MARK: Rename and delete

    func beginRename(_ target: RenameRequest.Target, current: String) {
        renameText = current
        renameRequest = RenameRequest(target: target, title: "重命名")
    }

    func commitRename() {
        guard let request = renameRequest else { return }
        renameRequest = nil
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        switch request.target {
        case .collection(let id):
            store.updateCollection(id) { $0.name = name }
        case .item(let collectionID, let itemID):
            store.updateCollection(collectionID) { $0.rename(itemID: itemID, to: name) }
            if let tab = tabs.requestTab(forItem: itemID) {
                tab.draft.name = name
                tab.baseline.name = name
            }
        case .environment(let id):
            store.updateEnvironment(id) { $0.name = name }
        }
    }

    func confirmDeleteCollection(_ collection: RequestCollection) {
        deleteRequest = DeleteRequest(
            target: .collection(collection.id),
            title: "删除集合「\(collection.name)」？",
            message: "集合中的 \(collection.requestCount) 个请求将被永久删除。"
        )
    }

    func confirmDeleteItem(_ item: CollectionItem, in collectionID: UUID) {
        deleteRequest = DeleteRequest(
            target: .item(collectionID: collectionID, itemID: item.id),
            title: "删除「\(item.name)」？",
            message: item.isFolder ? "文件夹及其中的所有请求将被删除。" : "该请求将被删除。"
        )
    }

    func confirmDeleteEnvironment(_ environment: APIEnvironment) {
        deleteRequest = DeleteRequest(
            target: .environment(environment.id),
            title: "删除环境「\(environment.name)」？",
            message: "环境中的 \(environment.variables.count) 个变量将被删除。"
        )
    }

    func confirmClearHistory() {
        deleteRequest = DeleteRequest(target: .history, title: "清空历史记录？", message: "所有 \(store.history.count) 条历史记录将被删除。")
    }

    func performDelete() {
        guard let request = deleteRequest else { return }
        deleteRequest = nil
        switch request.target {
        case .collection(let id):
            store.deleteCollection(id: id)
        case .item(let collectionID, let itemID):
            store.updateCollection(collectionID) { $0.remove(itemID: itemID) }
        case .environment(let id):
            store.deleteEnvironment(id: id)
        case .history:
            store.clearHistory()
        }
        tabs.reconcile(with: store)
    }

    // MARK: Import and export

    func importText(_ text: String) throws -> ImportOutcome {
        if CurlParser.looksLikeCurl(text) {
            try importCurl(text)
            return .curl
        }
        return try importData(Data(text.utf8))
    }

    func importData(_ data: Data) throws -> ImportOutcome {
        switch PostmanImporter.detect(data) {
        case .collection:
            let result = try PostmanImporter.importCollection(from: data)
            store.addCollection(result.collection)
            sidebarSection = .collections
            expandedItemIDs.insert(result.collection.id)
            return .collection(name: result.collection.name, requestCount: result.collection.requestCount, warnings: result.warnings)
        case .environment:
            let environment = try PostmanImporter.importEnvironment(from: data)
            store.addEnvironment(environment)
            sidebarSection = .environments
            return .environment(name: environment.name, variableCount: environment.variables.count)
        case .unknown:
            if let text = String(data: data, encoding: .utf8), CurlParser.looksLikeCurl(text) {
                try importCurl(text)
                return .curl
            }
            // Gives a specific error for invalid JSON or Postman v1 files.
            _ = try PostmanImporter.importCollection(from: data)
            throw PostmanImportError.unrecognizedFormat
        }
    }

    func importCurl(_ text: String) throws {
        let request = try CurlParser.parse(text)
        tabs.openRequest(request, collectionID: nil)
    }

    func exportCollection(_ id: UUID) {
        guard let collection = store.collection(id: id) else { return }
        export(suggestedName: "\(collection.name).postman_collection.json") {
            try PostmanExporter.export(collection)
        }
    }

    func exportEnvironment(_ id: UUID) {
        guard let environment = store.environment(id: id) else { return }
        let isGlobals = store.isGlobals(id)
        export(suggestedName: isGlobals ? "globals.postman_globals.json" : "\(environment.name).postman_environment.json") {
            try PostmanExporter.export(environment: environment, scope: isGlobals ? .globals : .environment)
        }
    }

    private func export(suggestedName: String, makeData: () throws -> Data) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName.replacingOccurrences(of: "/", with: "-")
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try makeData().write(to: url, options: .atomic)
        } catch {
            errorMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    #if DEBUG
    /// Launch arguments for scripted UI checks (screenshots without clicking):
    /// `-PostDataAutoSend YES`, `-PostDataDebugSection body|auth|…`,
    /// `-PostDataDebugSidebar environments|history`, `-PostDataDebugSheet code|import|save`.
    private func applyDebugLaunchOptions() {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: "PostDataDebugSection"), let section = RequestSection(rawValue: raw) {
            tabs.selectedRequest?.section = section
        }
        if let raw = defaults.string(forKey: "PostDataDebugSidebar"), let section = SidebarSection(rawValue: raw) {
            sidebarSection = section
        }
        if defaults.bool(forKey: "PostDataDebugDark") {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        let autoSend = defaults.bool(forKey: "PostDataAutoSend")
        let sheet = defaults.string(forKey: "PostDataDebugSheet")
        Task { @MainActor [weak self] in
            guard let self else { return }
            if autoSend { sendSelected() }
            try? await Task.sleep(for: .seconds(autoSend ? 2.5 : 0.5))
            switch sheet {
            case "code": if let state = tabs.selectedRequest { activeSheet = .codeSnippet(state) }
            case "save": if let state = tabs.selectedRequest { activeSheet = .saveRequest(state) }
            case "import": activeSheet = .importData
            default: break
            }
        }
        // `-PostDataDebugQuitAfter <seconds>` quits through the normal termination path.
        let quitAfter = defaults.double(forKey: "PostDataDebugQuitAfter")
        if quitAfter > 0 {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(quitAfter))
                NSApp.terminate(nil)
            }
        }
    }
    #endif

    // MARK: Session

    func saveSession() {
        let snapshotTabs = tabs.tabs.map { tab -> SessionSnapshot.Tab in
            switch tab.content {
            case .request(let state):
                SessionSnapshot.Tab(kind: .request, request: state.draft, collectionID: state.collectionID)
            case .environment(let id):
                SessionSnapshot.Tab(kind: .environment, environmentID: id)
            case .collection(let id):
                SessionSnapshot.Tab(kind: .collection, collectionID: id)
            }
        }
        store.saveSession(SessionSnapshot(tabs: snapshotTabs, selectedIndex: tabs.selectedIndex, expandedItemIDs: Array(expandedItemIDs)))
    }

    /// Saves everything synchronously; called when the app quits.
    func persistNow() {
        saveSession()
        store.flush()
    }

    private func restoreSession() {
        guard let session = store.storage.loadSession() else { return }
        expandedItemIDs = Set(session.expandedItemIDs)
        var restored: [EditorTab] = []
        var selectedIndex = session.selectedIndex
        for (index, tab) in session.tabs.enumerated() {
            let entry: EditorTab?
            switch tab.kind {
            case .request:
                if let draft = tab.request {
                    let saved = store.collection(id: tab.collectionID)?.request(withID: draft.id)
                    let state = RequestTabState(
                        request: draft,
                        collectionID: saved == nil ? nil : tab.collectionID,
                        baseline: saved
                    )
                    entry = EditorTab(id: state.id, content: .request(state))
                } else {
                    entry = nil
                }
            case .environment:
                entry = tab.environmentID.flatMap { store.environment(id: $0) }.map { EditorTab(id: UUID(), content: .environment($0.id)) }
            case .collection:
                entry = store.collection(id: tab.collectionID).map { EditorTab(id: UUID(), content: .collection($0.id)) }
            }
            if let entry {
                restored.append(entry)
            } else if let selected = selectedIndex, index < selected {
                selectedIndex = selected - 1
            }
        }
        tabs.restore(restored, selectedIndex: selectedIndex)
    }
}
