import PostDataKit
import SwiftUI

struct AppCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("新建请求") { model.tabs.newRequest() }
                .keyboardShortcut("t")
            Button("新建集合") { model.newCollection() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("新建环境") { model.newEnvironment() }
            Divider()
            Button("导入…") { model.activeSheet = .importData }
                .keyboardShortcut("o")
        }

        CommandGroup(replacing: .saveItem) {
            Button("保存请求") { model.saveSelected() }
                .keyboardShortcut("s")
            Button("另存为…") { model.saveSelectedAs() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
        }

        CommandMenu("请求") {
            Button("发送") { model.sendSelected() }
                .keyboardShortcut(.return, modifiers: .command)
            Button("取消请求") { model.tabs.selectedRequest?.cancel() }
                .keyboardShortcut(".", modifiers: .command)
            Divider()
            Button("生成代码…") {
                if let state = model.tabs.selectedRequest { model.activeSheet = .codeSnippet(state) }
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            Divider()
            Button("关闭标签") { model.closeSelectedTab() }
            Button("显示下一个标签") { model.tabs.selectNext() }
                .keyboardShortcut("]", modifiers: [.command, .shift])
            Button("显示上一个标签") { model.tabs.selectPrevious() }
                .keyboardShortcut("[", modifiers: [.command, .shift])
        }
    }
}
