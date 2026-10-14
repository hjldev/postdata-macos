import AppKit
import PostDataKit
import SwiftUI

@main
struct PostDataApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("PostData", id: "main") {
            ContentView()
                .environment(appDelegate.model)
                .frame(minWidth: 980, minHeight: 620)
        }
        .defaultSize(width: 1320, height: 840)
        .commands { AppCommands(model: appDelegate.model) }

        Settings {
            SettingsView()
                .environment(appDelegate.model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationDidResignActive(_ notification: Notification) {
        model.saveSession()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.persistNow()
    }
}
