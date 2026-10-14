import PostDataKit
import SwiftUI

struct AuthEditor: View {
    @Binding var auth: Auth
    /// Collections cannot inherit; requests and folders can.
    var allowsInherit = true
    var inheritedDescription = ""

    @State private var revealsSecret = false

    private var kinds: [Auth.Kind] {
        allowsInherit ? Auth.Kind.allCases : Auth.Kind.allCases.filter { $0 != .inherit }
    }

    var body: some View {
        Form {
            Picker("类型", selection: $auth.kind) {
                ForEach(kinds, id: \.self) { kind in
                    Text(kind.title).tag(kind)
                }
            }

            switch auth.kind {
            case .inherit:
                Text(inheritedDescription)
                    .foregroundStyle(.secondary)
            case .none:
                Text("该请求不使用认证。")
                    .foregroundStyle(.secondary)
            case .bearer:
                secretField("Token", text: $auth.bearerToken)
                Text("将发送请求头 Authorization: Bearer <token>，可使用 {{变量}}。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .basic:
                TextField("用户名", text: $auth.basicUsername)
                secretField("密码", text: $auth.basicPassword)
            case .apiKey:
                TextField("Key", text: $auth.apiKeyName)
                secretField("Value", text: $auth.apiKeyValue)
                Picker("添加到", selection: $auth.apiKeyLocation) {
                    Text("Header").tag(APIKeyLocation.header)
                    Text("Query Params").tag(APIKeyLocation.query)
                }
            }
        }
        .formStyle(.grouped)
        .font(.body)
        .textFieldStyle(.roundedBorder)
        .frame(maxWidth: 560, alignment: .leading)
    }

    @ViewBuilder
    private func secretField(_ title: String, text: Binding<String>) -> some View {
        HStack {
            if revealsSecret {
                TextField(title, text: text)
            } else {
                SecureField(title, text: text)
            }
            Button {
                revealsSecret.toggle()
            } label: {
                Image(systemName: revealsSecret ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
            .help(revealsSecret ? "隐藏" : "显示")
        }
    }
}
