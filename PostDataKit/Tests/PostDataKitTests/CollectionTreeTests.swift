import Foundation
import Testing
@testable import PostDataKit

@Suite("CollectionTree")
struct CollectionTreeTests {
    /// root
    ///  ├─ A (folder, bearer)
    ///  │   ├─ B (folder, inherit)
    ///  │   │   └─ r1 (inherit)
    ///  │   └─ r2 (basic)
    ///  └─ r3 (inherit)
    func makeCollection() -> (RequestCollection, ids: [String: UUID]) {
        let r1 = HTTPRequest(name: "r1", url: "https://x/1")
        let r2 = HTTPRequest(name: "r2", url: "https://x/2", auth: .basic(username: "u", password: "p"))
        let r3 = HTTPRequest(name: "r3", url: "https://x/3")
        let b = Folder(name: "B", items: [.request(r1)])
        let a = Folder(name: "A", items: [.folder(b), .request(r2)], auth: .bearer("folder-token"))
        let collection = RequestCollection(name: "C", items: [.folder(a), .request(r3)], auth: .apiKey(name: "k", value: "v"))
        return (collection, ["A": a.id, "B": b.id, "r1": r1.id, "r2": r2.id, "r3": r3.id])
    }

    @Test func findsItemsAndAncestors() throws {
        let (collection, ids) = makeCollection()
        #expect(collection.request(withID: ids["r1"]!)?.name == "r1")
        let ancestors = try #require(collection.ancestors(of: ids["r1"]!))
        #expect(ancestors.map(\.name) == ["A", "B"])
        #expect(collection.ancestors(of: ids["r3"]!) == [])
        #expect(collection.ancestors(of: UUID()) == nil)
        #expect(collection.allRequests.map(\.name) == ["r1", "r2", "r3"])
        #expect(collection.parentFolderID(of: ids["r2"]!) == ids["A"])
    }

    @Test func authInheritance() {
        let (collection, ids) = makeCollection()
        #expect(collection.effectiveAuth(forItem: ids["r1"]!).kind == .bearer)
        #expect(collection.effectiveAuth(forItem: ids["r1"]!).bearerToken == "folder-token")
        #expect(collection.authSourceName(forItem: ids["r1"]!) == "A")
        #expect(collection.effectiveAuth(forItem: ids["r2"]!).kind == .basic)
        #expect(collection.effectiveAuth(forItem: ids["r3"]!).kind == .apiKey)
        // A draft's own auth overrides what is stored.
        #expect(collection.effectiveAuth(forItem: ids["r2"]!, own: .inherit).kind == .bearer)
    }

    @Test func insertRemoveRename() {
        var (collection, ids) = makeCollection()
        let new = HTTPRequest(name: "new")
        let r1 = collection.insert(.request(new), intoFolder: ids["B"], at: 0)
        #expect(r1)
        #expect(collection.ancestors(of: new.id)?.map(\.name) == ["A", "B"])
        let r2 = collection.insert(.request(HTTPRequest()), intoFolder: UUID())
        #expect(!r2)
        let r3 = collection.rename(itemID: ids["B"]!, to: "Bee")
        #expect(r3)
        #expect(collection.item(withID: ids["B"]!)?.name == "Bee")
        let removed = collection.remove(itemID: ids["A"]!)
        #expect(removed?.name == "A")
        #expect(collection.allRequests.map(\.name) == ["r3"])
    }

    @Test func moveRejectsCycles() {
        var (collection, ids) = makeCollection()
        let r4 = collection.move(itemID: ids["A"]!, toFolder: ids["B"])
        #expect(!r4)
        let r5 = collection.move(itemID: ids["A"]!, toFolder: ids["A"])
        #expect(!r5)
        let r6 = collection.move(itemID: ids["r3"]!, toFolder: ids["r1"])
        #expect(!r6)
        let r7 = collection.move(itemID: ids["r3"]!, toFolder: ids["B"])
        #expect(r7)
        #expect(collection.ancestors(of: ids["r3"]!)?.map(\.name) == ["A", "B"])
        let r8 = collection.move(itemID: ids["B"]!, toFolder: nil, at: 0)
        #expect(r8)
        #expect(collection.items.first?.name == "B")
    }

    @Test func duplicateGivesFreshIDs() throws {
        var (collection, ids) = makeCollection()
        let duplicated = collection.duplicate(itemID: ids["A"]!)
        let copyID = try #require(duplicated)
        #expect(collection.items.map(\.name) == ["A", "A Copy", "r3"])
        let copy = try #require(collection.item(withID: copyID)?.folder)
        let originalIDs = Set(ids.values)
        var copiedIDs: [UUID] = []
        RequestCollection.walk(copy.items) { copiedIDs.append($0.id) }
        #expect(copiedIDs.count == 3)
        #expect(originalIDs.isDisjoint(with: copiedIDs))
    }

    @Test func destinationsListFolders() {
        let (collection, _) = makeCollection()
        #expect(collection.destinations().map(\.path) == ["C", "C / A", "C / A / B"])
    }

    @Test func codableRoundTrip() throws {
        let (collection, _) = makeCollection()
        let data = try JSONEncoder().encode(collection)
        let decoded = try JSONDecoder().decode(RequestCollection.self, from: data)
        #expect(decoded == collection)
    }

    @Test func decodingToleratesMissingFields() throws {
        let json = #"{"name":"Old","items":[{"type":"request","request":{"url":"https://x.dev/?a=1"}}]}"#
        let decoded = try JSONDecoder().decode(RequestCollection.self, from: Data(json.utf8))
        let request = try #require(decoded.items.first?.request)
        #expect(request.method == .get)
        #expect(request.auth.kind == .inherit)
        #expect(request.queryParams.map(\.key) == ["a"])
    }
}
