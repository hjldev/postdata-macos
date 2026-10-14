import Foundation

/// A place an item can be moved or saved to: a collection root or a folder inside it.
public struct CollectionDestination: Hashable, Sendable, Identifiable {
    public var collectionID: UUID
    /// Nil for the collection root.
    public var folderID: UUID?
    /// Human readable path, e.g. "My API / Users".
    public var path: String
    public var depth: Int

    public var id: String { "\(collectionID)/\(folderID?.uuidString ?? "root")" }

    public init(collectionID: UUID, folderID: UUID?, path: String, depth: Int) {
        self.collectionID = collectionID
        self.folderID = folderID
        self.path = path
        self.depth = depth
    }
}

extension RequestCollection {
    // MARK: Lookup

    public func item(withID id: UUID) -> CollectionItem? {
        Self.find(id, in: items)
    }

    public func request(withID id: UUID) -> HTTPRequest? {
        item(withID: id)?.request
    }

    public func contains(itemID id: UUID) -> Bool {
        item(withID: id) != nil
    }

    /// Folders from the root down to (not including) the item; nil when the item is not in this collection.
    public func ancestors(of id: UUID) -> [Folder]? {
        Self.ancestors(of: id, in: items, trail: [])
    }

    /// The folder directly containing the item; nil for root-level items or unknown ids.
    public func parentFolderID(of id: UUID) -> UUID? {
        ancestors(of: id)?.last?.id
    }

    /// All requests, depth first.
    public var allRequests: [HTTPRequest] {
        var result: [HTTPRequest] = []
        Self.walk(items) { item in
            if let request = item.request { result.append(request) }
        }
        return result
    }

    public var requestCount: Int { allRequests.count }

    /// The collection root followed by every folder, depth first.
    public func destinations() -> [CollectionDestination] {
        var result = [CollectionDestination(collectionID: id, folderID: nil, path: name, depth: 0)]
        func visit(_ items: [CollectionItem], path: String, depth: Int) {
            for case .folder(let folder) in items {
                let folderPath = path + " / " + folder.name
                result.append(CollectionDestination(collectionID: id, folderID: folder.id, path: folderPath, depth: depth))
                visit(folder.items, path: folderPath, depth: depth + 1)
            }
        }
        visit(items, path: name, depth: 1)
        return result
    }

    /// The auth that applies to an item, following `.inherit` up through folders to the collection.
    public func effectiveAuth(forItem id: UUID, own: Auth? = nil) -> Auth {
        let ownAuth = own ?? item(withID: id).map { item -> Auth in
            switch item {
            case .folder(let folder): folder.auth
            case .request(let request): request.auth
            }
        } ?? .inherit
        if ownAuth.kind != .inherit { return ownAuth }
        for folder in (ancestors(of: id) ?? []).reversed() where folder.auth.kind != .inherit {
            return folder.auth
        }
        return auth.kind == .inherit ? .none : auth
    }

    /// Where `.inherit` resolves to for an item: the name of the folder or collection providing the auth.
    public func authSourceName(forItem id: UUID) -> String {
        for folder in (ancestors(of: id) ?? []).reversed() where folder.auth.kind != .inherit {
            return folder.name
        }
        return name
    }

    // MARK: Mutation

    /// Inserts an item into a folder (or the root when `folderID` is nil). Returns false if the folder doesn't exist.
    @discardableResult
    public mutating func insert(_ item: CollectionItem, intoFolder folderID: UUID?, at index: Int? = nil) -> Bool {
        guard let folderID else {
            items.insert(item, at: Self.clamp(index, count: items.count))
            return true
        }
        return Self.mutateFolder(folderID, in: &items) { folder in
            folder.items.insert(item, at: Self.clamp(index, count: folder.items.count))
        }
    }

    /// Removes and returns an item anywhere in the tree.
    @discardableResult
    public mutating func remove(itemID id: UUID) -> CollectionItem? {
        Self.remove(id, from: &items)
    }

    /// Applies a change to an item in place. Returns false if not found.
    @discardableResult
    public mutating func update(itemID id: UUID, _ transform: (inout CollectionItem) -> Void) -> Bool {
        Self.mutateItem(id, in: &items, transform)
    }

    /// Replaces a request with the same id. Returns false if not found.
    @discardableResult
    public mutating func updateRequest(_ request: HTTPRequest) -> Bool {
        update(itemID: request.id) { item in
            if case .request = item { item = .request(request) }
        }
    }

    @discardableResult
    public mutating func rename(itemID id: UUID, to newName: String) -> Bool {
        update(itemID: id) { $0.name = newName }
    }

    /// Moves an item into another folder of this collection (or the root). Refuses to move a folder into itself.
    @discardableResult
    public mutating func move(itemID id: UUID, toFolder folderID: UUID?, at index: Int? = nil) -> Bool {
        if let folderID {
            if folderID == id { return false }
            if let moving = item(withID: id)?.folder, Self.find(folderID, in: moving.items) != nil { return false }
            if item(withID: folderID)?.folder == nil { return false }
        }
        guard let removed = remove(itemID: id) else { return false }
        return insert(removed, intoFolder: folderID, at: index)
    }

    /// Duplicates an item next to the original, with fresh ids throughout. Returns the copy's id.
    @discardableResult
    public mutating func duplicate(itemID id: UUID) -> UUID? {
        guard let original = item(withID: id) else { return nil }
        var copy = original.copyWithNewIDs()
        copy.name = original.name + " Copy"
        let parent = parentFolderID(of: id)
        let siblings = parent.flatMap { item(withID: $0)?.folder?.items } ?? items
        let index = siblings.firstIndex { $0.id == id }.map { $0 + 1 }
        insert(copy, intoFolder: parent, at: index)
        return copy.id
    }

    /// A copy of the whole collection with fresh ids throughout.
    public func copyWithNewIDs() -> RequestCollection {
        var copy = self
        copy.id = UUID()
        copy.items = items.map { $0.copyWithNewIDs() }
        copy.variables = variables.map { KeyValue(key: $0.key, value: $0.value, isEnabled: $0.isEnabled, description: $0.description) }
        return copy
    }

    // MARK: Helpers

    private static func clamp(_ index: Int?, count: Int) -> Int {
        guard let index else { return count }
        return min(max(index, 0), count)
    }

    static func find(_ id: UUID, in items: [CollectionItem]) -> CollectionItem? {
        for item in items {
            if item.id == id { return item }
            if case .folder(let folder) = item, let found = find(id, in: folder.items) { return found }
        }
        return nil
    }

    static func ancestors(of id: UUID, in items: [CollectionItem], trail: [Folder]) -> [Folder]? {
        for item in items {
            if item.id == id { return trail }
            if case .folder(let folder) = item, let found = ancestors(of: id, in: folder.items, trail: trail + [folder]) {
                return found
            }
        }
        return nil
    }

    /// Visits every item depth first.
    public static func walk(_ items: [CollectionItem], _ visit: (CollectionItem) -> Void) {
        for item in items {
            visit(item)
            if case .folder(let folder) = item { walk(folder.items, visit) }
        }
    }

    static func mutateItem(_ id: UUID, in items: inout [CollectionItem], _ transform: (inout CollectionItem) -> Void) -> Bool {
        for index in items.indices {
            if items[index].id == id {
                transform(&items[index])
                return true
            }
            if case .folder(var folder) = items[index] {
                if mutateItem(id, in: &folder.items, transform) {
                    items[index] = .folder(folder)
                    return true
                }
            }
        }
        return false
    }

    static func mutateFolder(_ id: UUID, in items: inout [CollectionItem], _ transform: (inout Folder) -> Void) -> Bool {
        var found = false
        _ = mutateItem(id, in: &items) { item in
            if case .folder(var folder) = item {
                transform(&folder)
                item = .folder(folder)
                found = true
            }
        }
        return found
    }

    static func remove(_ id: UUID, from items: inout [CollectionItem]) -> CollectionItem? {
        if let index = items.firstIndex(where: { $0.id == id }) {
            return items.remove(at: index)
        }
        for index in items.indices {
            if case .folder(var folder) = items[index], let removed = remove(id, from: &folder.items) {
                items[index] = .folder(folder)
                return removed
            }
        }
        return nil
    }
}

extension CollectionItem {
    /// A deep copy where this item and all descendants get new ids.
    public func copyWithNewIDs() -> CollectionItem {
        switch self {
        case .request(let request):
            return .request(request.withNewID())
        case .folder(var folder):
            folder.id = UUID()
            folder.items = folder.items.map { $0.copyWithNewIDs() }
            return .folder(folder)
        }
    }
}
