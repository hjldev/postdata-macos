import AppKit
import PostDataKit
import SwiftUI

/// Editor for multipart/form-data fields: each row is text or a file.
struct FormDataEditor: View {
    @Binding var fields: [FormDataField]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: 28)
                title("Key")
                title("Value")
                title("Content-Type").frame(maxWidth: 160)
                Color.clear.frame(width: 28)
            }
            .frame(height: 26)
            .background(Color(nsColor: .controlBackgroundColor))
            Divider()
            ScrollView {
                AppendableRows(items: $fields) { field, isPlaceholder, delete in
                    FormDataRow(field: field, isPlaceholder: isPlaceholder, onDelete: delete)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FormDataRow: View {
    @Binding var field: FormDataField
    let isPlaceholder: Bool
    let onDelete: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 0) {
            Toggle("", isOn: $field.isEnabled)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .frame(width: 28)
                .opacity(isPlaceholder ? 0 : 1)
                .disabled(isPlaceholder)
            HStack(spacing: 4) {
                TextField("Key", text: $field.key)
                    .textFieldStyle(.plain)
                Picker("", selection: $field.kind) {
                    Text("Text").tag(FormDataField.Kind.text)
                    Text("File").tag(FormDataField.Kind.file)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .controlSize(.small)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            Divider()
            Group {
                switch field.kind {
                case .text:
                    TextField("Value", text: $field.value)
                        .textFieldStyle(.plain)
                case .file:
                    HStack(spacing: 6) {
                        Button("选择文件…", action: chooseFile)
                            .controlSize(.small)
                        Text(field.filePath.map { ($0 as NSString).lastPathComponent } ?? "未选择")
                            .foregroundStyle(field.filePath == nil ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(field.filePath ?? "")
                    }
                }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            TextField("Auto", text: Binding(
                get: { field.contentType ?? "" },
                set: { field.contentType = $0.isEmpty ? nil : $0 }
            ))
            .textFieldStyle(.plain)
            .padding(.horizontal, 8)
            .frame(maxWidth: 160)
            Button(action: onDelete) { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .frame(width: 28)
                .opacity(isHovering && !isPlaceholder ? 1 : 0)
                .disabled(isPlaceholder)
        }
        .font(.system(size: 12, design: .monospaced))
        .frame(height: 28)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .opacity(field.isEnabled || isPlaceholder ? 1 : 0.5)
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            field.filePath = url.path(percentEncoded: false)
        }
    }
}
