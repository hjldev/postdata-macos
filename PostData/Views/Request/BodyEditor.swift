import AppKit
import PostDataKit
import SwiftUI

struct BodyEditor: View {
    @Binding var requestBody: RequestBody
    let method: HTTPMethod
    @AppStorage(AppSettings.editorFontSizeKey) private var fontSize = 12.0
    @State private var beautifyFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Picker("", selection: $requestBody.mode) {
                    ForEach(RequestBody.Mode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                .horizontalRadioGroupLayout()
                .labelsHidden()

                if requestBody.mode == .raw {
                    Picker("", selection: $requestBody.rawLanguage) {
                        ForEach(RequestBody.RawLanguage.allCases, id: \.self) { language in
                            Text(language.title).tag(language)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Spacer()
                    if requestBody.rawLanguage == .json {
                        Button("美化") { beautify() }
                            .help("格式化 JSON")
                    }
                } else {
                    Spacer()
                }
            }

            if !method.allowsBody, requestBody.mode != .none {
                Label("\(method.rawValue) 请求的 Body 不会被发送。", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            switch requestBody.mode {
            case .none:
                Text("该请求没有 Body")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .formData:
                FormDataEditor(fields: $requestBody.formData)
            case .urlEncoded:
                KeyValueEditor(items: $requestBody.urlEncoded)
            case .raw:
                CodeTextView(
                    text: $requestBody.raw,
                    language: requestBody.rawLanguage == .json ? .json : .plain,
                    highlightsVariables: true,
                    fontSize: fontSize
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
            case .binary:
                binaryPicker
            }
        }
        .alert("JSON 格式不正确", isPresented: $beautifyFailed) {
            Button("好") {}
        } message: {
            Text("无法格式化：Body 不是有效的 JSON（可能包含未替换的 {{变量}}）。")
        }
    }

    private var binaryPicker: some View {
        HStack(spacing: 10) {
            Button("选择文件…") {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = false
                panel.allowsMultipleSelection = false
                if panel.runModal() == .OK, let url = panel.url {
                    requestBody.binaryFilePath = url.path(percentEncoded: false)
                }
            }
            if let path = requestBody.binaryFilePath {
                Image(systemName: "doc")
                Text(path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Button {
                    requestBody.binaryFilePath = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
            } else {
                Text("未选择文件").foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func beautify() {
        if let pretty = JSONFormatter.prettyPrint(requestBody.raw) {
            requestBody.raw = pretty
        } else {
            beautifyFailed = true
        }
    }
}

struct RequestSettingsView: View {
    @Binding var settings: RequestSettings

    var body: some View {
        Form {
            Toggle("自动跟随重定向", isOn: $settings.followRedirects)
            Toggle("校验 SSL 证书", isOn: $settings.validateSSL)
            if !settings.validateSSL {
                Text("将接受自签名或无效证书，仅建议用于本地调试。")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            TextField("超时（秒）", value: $settings.timeout, format: .number)
                .help("0 表示不限制")
        }
        .formStyle(.grouped)
        .frame(maxWidth: 520, alignment: .leading)
    }
}
