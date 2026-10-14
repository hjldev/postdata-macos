import Foundation
import Observation
import PostDataKit

enum RequestSection: String, CaseIterable, Identifiable {
    case params, auth, headers, body, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .params: "Params"
        case .auth: "Auth"
        case .headers: "Headers"
        case .body: "Body"
        case .settings: "Settings"
        }
    }
}

struct LoadedResponse {
    let response: HTTPResponse
    let content: ResponseContent
    let receivedAt: Date
}

enum ResponseState {
    case idle
    case loading(startedAt: Date)
    case loaded(LoadedResponse)
    case failed(String)
    case cancelled

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

/// One open request tab: the editable draft, its saved baseline and the last response.
@Observable
final class RequestTabState: Identifiable {
    let id = UUID()
    var draft: HTTPRequest
    /// The last saved (or opened) version; the tab is dirty when the draft differs.
    var baseline: HTTPRequest
    /// The collection the request is saved in; nil for unsaved requests.
    var collectionID: UUID?
    var section: RequestSection
    var response: ResponseState = .idle
    @ObservationIgnored var sendTask: Task<Void, Never>?

    init(request: HTTPRequest, collectionID: UUID?, baseline: HTTPRequest? = nil) {
        draft = request
        self.baseline = baseline ?? request
        self.collectionID = collectionID
        section = request.body.mode != .none && request.method.allowsBody ? .body : .params
    }

    var isDirty: Bool { draft != baseline }

    func cancel() {
        sendTask?.cancel()
        sendTask = nil
        if response.isLoading { response = .cancelled }
    }

    /// Replaces the request content with an imported one (e.g. a pasted cURL), keeping identity.
    func applyImported(_ imported: HTTPRequest) {
        var request = imported
        request.id = draft.id
        if collectionID != nil || draft.name != HTTPRequest().name {
            request.name = draft.name
        }
        draft = request
        section = request.body.mode != .none && request.method.allowsBody ? .body : .params
    }
}
