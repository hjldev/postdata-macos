import Foundation
import PostDataKit

/// UserDefaults-backed preferences shared by the Settings window and the app logic.
enum AppSettings {
    static let timeoutKey = "defaultTimeout"
    static let validateSSLKey = "defaultValidateSSL"
    static let followRedirectsKey = "defaultFollowRedirects"
    static let historyLimitKey = "historyLimit"
    static let editorFontSizeKey = "editorFontSize"
    static let wrapLinesKey = "wrapResponseLines"
    static let codeGeneratorKey = "codeSnippetGenerator"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            timeoutKey: 30.0,
            validateSSLKey: true,
            followRedirectsKey: true,
            historyLimitKey: 500,
            editorFontSizeKey: 12.0,
            wrapLinesKey: true,
            codeGeneratorKey: "curl",
        ])
    }

    static var defaultRequestSettings: RequestSettings {
        let defaults = UserDefaults.standard
        return RequestSettings(
            followRedirects: defaults.bool(forKey: followRedirectsKey),
            timeout: defaults.double(forKey: timeoutKey),
            validateSSL: defaults.bool(forKey: validateSSLKey)
        )
    }

    static var historyLimit: Int {
        max(0, UserDefaults.standard.integer(forKey: historyLimitKey))
    }

    /// Where the workspace lives. `-PostDataDataDirectory <path>` overrides it,
    /// e.g. to keep a separate workspace for testing.
    static var dataDirectory: URL {
        if let path = UserDefaults.standard.string(forKey: "PostDataDataDirectory"), !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        }
        return WorkspaceStorage.defaultRootURL
    }
}
