import AppKit
import PostDataKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("通用", systemImage: "gearshape") {
                GeneralSettings()
            }
            Tab("编辑器", systemImage: "textformat") {
                EditorSettings()
            }
            Tab("数据", systemImage: "externaldrive") {
                DataSettings()
            }
        }
        .frame(width: 500, height: 320)
    }
}

private struct GeneralSettings: View {
    @AppStorage(AppSettings.timeoutKey) private var timeout = 30.0
    @AppStorage(AppSettings.validateSSLKey) private var validateSSL = true
    @AppStorage(AppSettings.followRedirectsKey) private var followRedirects = true
    @AppStorage(AppSettings.historyLimitKey) private var historyLimit = 500

    var body: some View {
        Form {
            Section("新请求的默认设置") {
                TextField("超时（秒，0 为不限制）", value: $timeout, format: .number)
                Toggle("校验 SSL 证书", isOn: $validateSSL)
                Toggle("自动跟随重定向", isOn: $followRedirects)
            }
            Section("历史记录") {
                Picker("最多保留", selection: $historyLimit) {
                    Text("不记录").tag(0)
                    Text("100 条").tag(100)
                    Text("500 条").tag(500)
                    Text("1000 条").tag(1000)
                    Text("5000 条").tag(5000)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct EditorSettings: View {
    @AppStorage(AppSettings.editorFontSizeKey) private var fontSize = 12.0
    @AppStorage(AppSettings.wrapLinesKey) private var wrapLines = true

    var body: some View {
        Form {
            Section {
                Stepper(value: $fontSize, in: 9...24, step: 1) {
                    LabeledContent("代码字号", value: "\(Int(fontSize)) pt")
                }
                Toggle("响应内容自动换行", isOn: $wrapLines)
            }
            Section("预览") {
                Text(#"{ "message": "Hello, PostData" }"#)
                    .font(.system(size: fontSize, design: .monospaced))
            }
        }
        .formStyle(.grouped)
    }
}

private struct DataSettings: View {
    var body: some View {
        Form {
            Section("数据位置") {
                LabeledContent("目录") {
                    Text(AppSettings.dataDirectory.path(percentEncoded: false))
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                Button("在 Finder 中显示") {
                    let url = AppSettings.dataDirectory
                    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            Section {
                Text("集合、环境和历史记录以 JSON 文件保存，可以直接备份或纳入版本管理。")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
