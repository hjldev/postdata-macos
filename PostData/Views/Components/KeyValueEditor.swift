import PostDataKit
import SwiftUI

/// Rows that can be blank; the editor keeps one blank row at the end for adding entries.
protocol AppendableRow: Identifiable where ID == UUID {
    var isBlank: Bool { get }
    static func blankRow() -> Self
}

extension KeyValue: AppendableRow {
    static func blankRow() -> KeyValue { KeyValue() }
}

extension FormDataField: AppendableRow {
    static func blankRow() -> FormDataField { FormDataField() }
}

/// A list of editable rows followed by a placeholder row. Typing into the placeholder turns it
/// into a real row while keeping its identity, so the text field keeps focus.
struct AppendableRows<Item: AppendableRow, Row: View>: View {
    @Binding var items: [Item]
    @ViewBuilder let row: (_ item: Binding<Item>, _ isPlaceholder: Bool, _ delete: @escaping () -> Void) -> Row
    @State private var placeholder = Item.blankRow()

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(items + [placeholder]) { item in
                let isPlaceholder = item.id == placeholder.id
                row(binding(for: item.id), isPlaceholder) {
                    items.removeAll { $0.id == item.id }
                }
                Divider()
            }
        }
    }

    private func binding(for id: UUID) -> Binding<Item> {
        Binding(
            get: { items.first { $0.id == id } ?? placeholder },
            set: { newValue in
                if let index = items.firstIndex(where: { $0.id == id }) {
                    items[index] = newValue
                } else if id == placeholder.id {
                    if newValue.isBlank {
                        placeholder = newValue
                    } else {
                        items.append(newValue)
                        placeholder = Item.blankRow()
                    }
                }
            }
        )
    }
}

/// Postman-style key/value table with enable checkboxes, an auto-appended blank row and bulk edit.
struct KeyValueEditor: View {
    @Binding var items: [KeyValue]
    var keyPlaceholder = "Key"
    var valuePlaceholder = "Value"
    var showsDescription = true
    var allowsBulkEdit = true

    @State private var isBulkEditing = false
    @State private var bulkText = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if isBulkEditing {
                CodeTextView(text: $bulkText, highlightsVariables: true)
                    .onChange(of: bulkText) { _, newValue in
                        items = KeyValueBulkFormat.parse(newValue, existing: items)
                    }
            } else {
                ScrollView {
                    AppendableRows(items: $items) { item, isPlaceholder, delete in
                        KeyValueRow(
                            item: item,
                            isPlaceholder: isPlaceholder,
                            keyPlaceholder: keyPlaceholder,
                            valuePlaceholder: valuePlaceholder,
                            showsDescription: showsDescription,
                            onDelete: delete
                        )
                    }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
    }

    private var header: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 28)
            columnTitle(keyPlaceholder)
            columnTitle(valuePlaceholder)
            if showsDescription { columnTitle("Description") }
            if allowsBulkEdit {
                Button(isBulkEditing ? "表格编辑" : "批量编辑") {
                    if !isBulkEditing { bulkText = KeyValueBulkFormat.serialize(items) }
                    isBulkEditing.toggle()
                }
                .buttonStyle(.link)
                .font(.caption)
                .padding(.horizontal, 8)
            } else {
                Color.clear.frame(width: 28)
            }
        }
        .frame(height: 26)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func columnTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct KeyValueRow: View {
    @Binding var item: KeyValue
    let isPlaceholder: Bool
    var keyPlaceholder = "Key"
    var valuePlaceholder = "Value"
    var showsDescription = true
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 0) {
            Toggle("", isOn: $item.isEnabled)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .frame(width: 28)
                .opacity(isPlaceholder ? 0 : 1)
                .disabled(isPlaceholder)
            cell(TextField(keyPlaceholder, text: $item.key))
            Divider()
            cell(TextField(valuePlaceholder, text: $item.value))
            if showsDescription {
                Divider()
                cell(TextField("Description", text: $item.description))
            }
            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("删除")
            .frame(width: 28)
            .opacity(isHovering && !isPlaceholder ? 1 : 0)
            .disabled(isPlaceholder)
        }
        .frame(height: 28)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .opacity(item.isEnabled || isPlaceholder ? 1 : 0.5)
    }

    private func cell(_ field: TextField<Text>) -> some View {
        field
            .textFieldStyle(.plain)
            .font(.system(size: 12, design: .monospaced))
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
