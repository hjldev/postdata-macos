import Foundation
import os

/// Environments, globals and the active selection, stored together.
public struct EnvironmentsState: Hashable, Sendable, Codable {
    public var globals: APIEnvironment
    public var environments: [APIEnvironment]
    public var activeEnvironmentID: UUID?

    public init(globals: APIEnvironment = APIEnvironment(name: "Globals"), environments: [APIEnvironment] = [], activeEnvironmentID: UUID? = nil) {
        self.globals = globals
        self.environments = environments
        self.activeEnvironmentID = activeEnvironmentID
    }
}

/// Open tabs, restored on next launch (including unsaved drafts).
public struct SessionSnapshot: Hashable, Sendable, Codable {
    public enum TabKind: String, Hashable, Sendable, Codable {
        case request, environment, collection
    }

    public struct Tab: Hashable, Sendable, Codable {
        public var kind: TabKind
        /// The draft for request tabs.
        public var request: HTTPRequest?
        /// The collection a request tab is saved in, or the collection of a collection tab.
        public var collectionID: UUID?
        /// The environment of an environment tab.
        public var environmentID: UUID?

        public init(kind: TabKind, request: HTTPRequest? = nil, collectionID: UUID? = nil, environmentID: UUID? = nil) {
            self.kind = kind
            self.request = request
            self.collectionID = collectionID
            self.environmentID = environmentID
        }
    }

    public var tabs: [Tab]
    public var selectedIndex: Int?
    public var expandedItemIDs: [UUID]

    public init(tabs: [Tab] = [], selectedIndex: Int? = nil, expandedItemIDs: [UUID] = []) {
        self.tabs = tabs
        self.selectedIndex = selectedIndex
        self.expandedItemIDs = expandedItemIDs
    }
}

/// Reads and writes the workspace as JSON files:
///
///     <root>/collections/<uuid>.json
///     <root>/environments.json
///     <root>/history.json
///     <root>/session.json
///
/// Every file is wrapped as `{"version": 1, "data": …}` to allow future migrations.
/// Writes are atomic. The type is thread-safe; callers decide when to save.
public final class WorkspaceStorage: Sendable {
    public static let currentVersion = 1

    public let rootURL: URL
    private let logger = Logger(subsystem: "dev.postdata.PostData", category: "storage")

    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    public static var defaultRootURL: URL {
        URL.applicationSupportDirectory.appending(path: "PostData", directoryHint: .isDirectory)
    }

    private var collectionsURL: URL { rootURL.appending(path: "collections", directoryHint: .isDirectory) }
    private var environmentsURL: URL { rootURL.appending(path: "environments.json") }
    private var historyURL: URL { rootURL.appending(path: "history.json") }
    private var sessionURL: URL { rootURL.appending(path: "session.json") }

    private func collectionURL(_ id: UUID) -> URL {
        collectionsURL.appending(path: "\(id.uuidString).json")
    }

    // MARK: Collections

    /// Loads every collection file; unreadable files are skipped (and logged) instead of failing the whole load.
    public func loadCollections() -> [RequestCollection] {
        let files = (try? FileManager.default.contentsOfDirectory(at: collectionsURL, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap { url in
            do {
                return try read(RequestCollection.self, from: url)
            } catch {
                logger.error("Skipping unreadable collection \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
    }

    public func saveCollection(_ collection: RequestCollection) throws {
        try write(collection, to: collectionURL(collection.id))
    }

    public func deleteCollection(id: UUID) throws {
        let url = collectionURL(id)
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: url)
        }
    }

    // MARK: Environments

    public func loadEnvironments() -> EnvironmentsState? {
        try? read(EnvironmentsState.self, from: environmentsURL)
    }

    public func saveEnvironments(_ state: EnvironmentsState) throws {
        try write(state, to: environmentsURL)
    }

    // MARK: History

    public func loadHistory() -> [HistoryEntry] {
        (try? read([HistoryEntry].self, from: historyURL)) ?? []
    }

    public func saveHistory(_ history: [HistoryEntry]) throws {
        try write(history, to: historyURL)
    }

    // MARK: Session

    public func loadSession() -> SessionSnapshot? {
        try? read(SessionSnapshot.self, from: sessionURL)
    }

    public func saveSession(_ session: SessionSnapshot) throws {
        try write(session, to: sessionURL)
    }

    // MARK: Encoding

    private struct Envelope<Payload: Codable>: Codable {
        var version: Int
        var data: Payload
    }

    private struct VersionProbe: Decodable {
        var version: Int
    }

    private func read<T: Codable>(_ type: T.Type, from url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let probe = try decoder.decode(VersionProbe.self, from: data)
        guard probe.version <= Self.currentVersion else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "File was written by a newer version of PostData"])
        }
        return try decoder.decode(Envelope<T>.self, from: data).data
    }

    private func write<T: Codable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(Envelope(version: Self.currentVersion, data: value))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
