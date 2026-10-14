import PostDataKit
import SwiftUI

struct HistorySidebar: View {
    @Environment(AppModel.self) private var model
    let searchText: String

    var body: some View {
        List(selection: selection) {
            ForEach(groups, id: \.day) { group in
                Section(dayTitle(group.day)) {
                    ForEach(group.entries) { entry in
                        HistoryRow(entry: entry)
                            .tag(entry.id)
                            .contextMenu {
                                Button("在新标签中打开") { open(entry) }
                                Button("保存到集合…") {
                                    let state = open(entry)
                                    model.activeSheet = .saveRequest(state)
                                }
                                Divider()
                                Button("删除", role: .destructive) { model.store.deleteHistory(id: entry.id) }
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if model.store.history.isEmpty {
                ContentUnavailableView("没有历史记录", systemImage: "clock", description: Text("发送过的请求会出现在这里。"))
            } else if groups.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }

    /// Clicking an entry opens a copy in a new tab; the selection itself is not kept.
    private var selection: Binding<UUID?> {
        Binding(
            get: { nil },
            set: { id in
                if let id, let entry = model.store.history.first(where: { $0.id == id }) { open(entry) }
            }
        )
    }

    @discardableResult
    private func open(_ entry: HistoryEntry) -> RequestTabState {
        model.tabs.openRequest(entry.request.withNewID(), collectionID: nil)
    }

    private var groups: [(day: Date, entries: [HistoryEntry])] {
        let calendar = Calendar.current
        let entries = searchText.isEmpty ? model.store.history : model.store.history.filter {
            $0.request.url.localizedCaseInsensitiveContains(searchText) || $0.request.name.localizedCaseInsensitiveContains(searchText)
        }
        let grouped = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0]!) }
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "今天" }
        if calendar.isDateInYesterday(day) { return "昨天" }
        return day.formatted(date: .abbreviated, time: .omitted)
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry

    var body: some View {
        HStack(spacing: 6) {
            MethodLabel(method: entry.request.method)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.request.url.isEmpty ? entry.request.name : entry.request.url)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(entry.date.formatted(date: .omitted, time: .shortened))
                    if let duration = entry.duration { Text(Formatters.duration(duration)) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if let status = entry.statusCode {
                Text("\(status)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(status.statusColor)
            } else if entry.errorMessage != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(entry.errorMessage ?? "")
            }
        }
        .help(entry.request.url)
    }
}
