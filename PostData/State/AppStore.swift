import Foundation
import Observation
import os
import PostDataKit

/// Where an id lives in the workspace.
enum ItemLocation {
    case collection(RequestCollection)
    case folder(collectionID: UUID, folder: Folder)
    case request(collectionID: UUID, request: HTTPRequest)
}

/// The persistent workspace: collections, environments and history.
///
/// Every mutation goes through a method here so changes are tracked and written to disk
/// (debounced, on a serial background queue).
@Observable
final class AppStore {
    private(set) var collections: [RequestCollection] = []
    private(set) var environmentsState: EnvironmentsState
    private(set) var history: [HistoryEntry] = []

    @ObservationIgnored let storage: WorkspaceStorage
    @ObservationIgnored let client = HTTPClient()
    @ObservationIgnored private let writeQueue = DispatchQueue(label: "dev.postdata.storage", qos: .utility)
    @ObservationIgnored private let logger = Logger(subsystem: "dev.postdata.PostData", category: "store")
    @ObservationIgnored private var pendingCollectionSaves = Set<UUID>()
    @ObservationIgnored private var pendingCollectionDeletes = Set<UUID>()
    @ObservationIgnored private var environmentsDirty = false
    @ObservationIgnored private var historyDirty = false
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init(storage: WorkspaceStorage) {
        self.storage = storage
        environmentsState = storage.loadEnvironments() ?? EnvironmentsState()
        collections = storage.loadCollections()
        history = storage.loadHistory()
        sortCollections()
    }

    // MARK: Collections

    func collection(id: UUID?) -> RequestCollection? {
        guard let id else { return nil }
        return collections.first { $0.id == id }
    }

    func locate(_ id: UUID) -> ItemLocation? {
        for collection in collections {
            if collection.id == id { return .collection(collection) }
            switch collection.item(withID: id) {
            case .folder(let folder): return .folder(collectionID: collection.id, folder: folder)
            case .request(let request): return .request(collectionID: collection.id, request: request)
            case nil: continue
            }
        }
        return nil
    }

    @discardableResult
    func addCollection(name: String) -> RequestCollection {
        let collection = RequestCollection(name: name)
        addCollection(collection)
        return collection
    }

    func addCollection(_ collection: RequestCollection) {
        collections.append(collection)
        sortCollections()
        markCollectionDirty(collection.id)
    }

    /// Applies a change to a collection. Returns false when it no longer exists.
    @discardableResult
    func updateCollection(_ id: UUID, _ change: (inout RequestCollection) -> Void) -> Bool {
        guard let index = collections.firstIndex(where: { $0.id == id }) else { return false }
        let oldName = collections[index].name
        change(&collections[index])
        if collections[index].name != oldName { sortCollections() }
        markCollectionDirty(id)
        return true
    }

    func deleteCollection(id: UUID) {
        collections.removeAll { $0.id == id }
        pendingCollectionSaves.remove(id)
        pendingCollectionDeletes.insert(id)
        scheduleSave()
    }

    @discardableResult
    func duplicateCollection(id: UUID) -> RequestCollection? {
        guard let original = collection(id: id) else { return nil }
        var copy = original.copyWithNewIDs()
        copy.name = original.name + " Copy"
        addCollection(copy)
        return copy
    }

    /// Every collection root and folder, for "Save to…" and "Move to…" pickers.
    var allDestinations: [CollectionDestination] {
        collections.flatMap { $0.destinations() }
    }

    /// Adds an item under a destination. Returns false if the destination disappeared.
    @discardableResult
    func insert(_ item: CollectionItem, into destination: CollectionDestination) -> Bool {
        var inserted = false
        updateCollection(destination.collectionID) { collection in
            inserted = collection.insert(item, intoFolder: destination.folderID)
        }
        return inserted
    }

    /// Replaces a saved request. Returns false when it is no longer in the collection.
    @discardableResult
    func updateRequest(_ request: HTTPRequest, in collectionID: UUID) -> Bool {
        var updated = false
        updateCollection(collectionID) { collection in
            updated = collection.updateRequest(request)
        }
        return updated
    }

    // MARK: Environments

    var globals: APIEnvironment { environmentsState.globals }
    var environments: [APIEnvironment] { environmentsState.environments }

    var activeEnvironmentID: UUID? {
        get { environmentsState.activeEnvironmentID }
        set {
            environmentsState.activeEnvironmentID = newValue
            markEnvironmentsDirty()
        }
    }

    var activeEnvironment: APIEnvironment? {
        guard let id = environmentsState.activeEnvironmentID else { return nil }
        return environments.first { $0.id == id }
    }

    func isGlobals(_ id: UUID) -> Bool { id == environmentsState.globals.id }

    /// An environment by id, including globals.
    func environment(id: UUID) -> APIEnvironment? {
        if isGlobals(id) { return environmentsState.globals }
        return environments.first { $0.id == id }
    }

    @discardableResult
    func addEnvironment(name: String) -> APIEnvironment {
        let environment = APIEnvironment(name: name)
        addEnvironment(environment)
        return environment
    }

    func addEnvironment(_ environment: APIEnvironment) {
        environmentsState.environments.append(environment)
        markEnvironmentsDirty()
    }

    func updateEnvironment(_ id: UUID, _ change: (inout APIEnvironment) -> Void) {
        if isGlobals(id) {
            change(&environmentsState.globals)
        } else if let index = environmentsState.environments.firstIndex(where: { $0.id == id }) {
            change(&environmentsState.environments[index])
        } else {
            return
        }
        markEnvironmentsDirty()
    }

    func deleteEnvironment(id: UUID) {
        guard !isGlobals(id) else { return }
        environmentsState.environments.removeAll { $0.id == id }
        if environmentsState.activeEnvironmentID == id { environmentsState.activeEnvironmentID = nil }
        markEnvironmentsDirty()
    }

    @discardableResult
    func duplicateEnvironment(id: UUID) -> APIEnvironment? {
        guard let original = environment(id: id) else { return nil }
        let copy = APIEnvironment(
            name: original.name + " Copy",
            variables: original.variables.map { KeyValue(key: $0.key, value: $0.value, isEnabled: $0.isEnabled, description: $0.description) }
        )
        addEnvironment(copy)
        return copy
    }

    // MARK: Variables and auth

    /// Globals < collection variables < active environment.
    func variableResolver(collectionID: UUID?) -> VariableResolver {
        VariableResolver(
            globals: globals.variables,
            collection: collection(id: collectionID)?.variables ?? [],
            environment: activeEnvironment?.variables ?? []
        )
    }

    /// The auth a draft would be sent with, following inheritance when it is saved in a collection.
    func effectiveAuth(for request: HTTPRequest, collectionID: UUID?) -> Auth {
        if let collection = collection(id: collectionID), collection.contains(itemID: request.id) {
            return collection.effectiveAuth(forItem: request.id, own: request.auth)
        }
        return request.auth.kind == .inherit ? .none : request.auth
    }

    /// Explains what `.inherit` resolves to, for the Auth editor.
    func inheritedAuthDescription(for request: HTTPRequest, collectionID: UUID?) -> String {
        guard let collection = collection(id: collectionID), collection.contains(itemID: request.id) else {
            return "请求尚未保存到集合，不会使用任何认证。"
        }
        let auth = collection.effectiveAuth(forItem: request.id, own: .inherit)
        let source = collection.authSourceName(forItem: request.id)
        return auth.kind == .none
            ? "继承自「\(source)」：不使用认证。"
            : "继承自「\(source)」：\(auth.kind.title)。"
    }

    // MARK: History

    func addHistory(_ entry: HistoryEntry) {
        let limit = AppSettings.historyLimit
        guard limit > 0 else { return }
        history.insert(entry, at: 0)
        if history.count > limit { history.removeLast(history.count - limit) }
        markHistoryDirty()
    }

    func deleteHistory(id: UUID) {
        history.removeAll { $0.id == id }
        markHistoryDirty()
    }

    func clearHistory() {
        history.removeAll()
        markHistoryDirty()
    }

    // MARK: Persistence

    func saveSession(_ snapshot: SessionSnapshot) {
        let storage = self.storage
        let logger = self.logger
        writeQueue.async {
            do { try storage.saveSession(snapshot) } catch {
                logger.error("Saving session failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Writes everything pending and waits for all queued writes, for app termination.
    func flush() {
        saveTask?.cancel()
        writePending()
        writeQueue.sync {}
    }

    private func sortCollections() {
        collections.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func markCollectionDirty(_ id: UUID) {
        pendingCollectionSaves.insert(id)
        pendingCollectionDeletes.remove(id)
        scheduleSave()
    }

    private func markEnvironmentsDirty() {
        environmentsDirty = true
        scheduleSave()
    }

    private func markHistoryDirty() {
        historyDirty = true
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.writePending()
        }
    }

    /// Snapshots dirty state on the main actor, then writes it on the serial queue.
    private func writePending() {
        let collectionsToSave = pendingCollectionSaves.compactMap { collection(id: $0) }
        let collectionsToDelete = pendingCollectionDeletes
        let environments = environmentsDirty ? environmentsState : nil
        let history = historyDirty ? self.history : nil
        pendingCollectionSaves.removeAll()
        pendingCollectionDeletes.removeAll()
        environmentsDirty = false
        historyDirty = false

        guard !collectionsToSave.isEmpty || !collectionsToDelete.isEmpty || environments != nil || history != nil else { return }
        let storage = self.storage
        let logger = self.logger
        writeQueue.async {
            do {
                for collection in collectionsToSave { try storage.saveCollection(collection) }
                for id in collectionsToDelete { try storage.deleteCollection(id: id) }
                if let environments { try storage.saveEnvironments(environments) }
                if let history { try storage.saveHistory(history) }
            } catch {
                logger.error("Saving workspace failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
