import PostDataKit
import SwiftUI

enum ResponseSection: String, CaseIterable, Identifiable {
    case body, headers, cookies
    var id: String { rawValue }
}

struct ResponseView: View {
    let state: RequestTabState
    @State private var section: ResponseSection = .body

    var body: some View {
        Group {
            switch state.response {
            case .idle:
                ContentUnavailableView {
                    Label("尚未发送请求", systemImage: "paperplane")
                } description: {
                    Text("输入 URL 后点击「发送」或按 ⌘↩，响应会显示在这里。")
                }
            case .loading(let startedAt):
                VStack(spacing: 12) {
                    ProgressView()
                    TimelineView(.periodic(from: startedAt, by: 0.1)) { context in
                        Text("正在发送… \(Formatters.duration(context.date.timeIntervalSince(startedAt)))")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Button("取消") { state.cancel() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .cancelled:
                ContentUnavailableView("请求已取消", systemImage: "xmark.circle")
            case .failed(let message):
                ContentUnavailableView {
                    Label("请求失败", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message).textSelection(.enabled)
                }
            case .loaded(let loaded):
                loadedView(loaded)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func loadedView(_ loaded: LoadedResponse) -> some View {
        let response = loaded.response
        return VStack(spacing: 0) {
            HStack(spacing: 14) {
                Picker("", selection: $section) {
                    Text("Body").tag(ResponseSection.body)
                    Text("Headers (\(response.headers.count))").tag(ResponseSection.headers)
                    Text("Cookies (\(response.cookies.count))").tag(ResponseSection.cookies)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
                StatusSummary(response: response)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            Divider()
            switch section {
            case .body:
                ResponseBodyView(loaded: loaded)
            case .headers:
                HeadersTable(headers: response.headers)
            case .cookies:
                CookiesTable(cookies: response.cookies)
            }
        }
    }
}

/// Status code, total time (click for a phase breakdown) and size.
private struct StatusSummary: View {
    let response: HTTPResponse
    #if DEBUG
    @State private var showsTimings = UserDefaults.standard.bool(forKey: "PostDataDebugShowTimings")
    #else
    @State private var showsTimings = false
    #endif

    var body: some View {
        HStack(spacing: 14) {
            Text("\(response.statusCode) \(response.statusText)")
                .font(.callout.weight(.semibold))
                .foregroundStyle(response.statusCode.statusColor)
                .textSelection(.enabled)
            if !response.redirects.isEmpty {
                Button {
                    showsTimings = true
                } label: {
                    Label("\(response.redirects.count) 次重定向", systemImage: "arrow.turn.up.right")
                }
                .buttonStyle(.borderless)
                .help(redirectSummary)
            }
            Button {
                showsTimings.toggle()
            } label: {
                Label(Formatters.duration(response.duration), systemImage: "clock")
            }
            .buttonStyle(.borderless)
            .help("查看耗时明细")
            .popover(isPresented: $showsTimings, arrowEdge: .bottom) {
                TimingsView(response: response)
            }
            Label(Formatters.bytes(response.bodySize + response.headersSize), systemImage: "arrow.down.circle")
                .help("Body \(Formatters.bytes(response.bodySize)) + Headers \(Formatters.bytes(response.headersSize))")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }

    private var redirectSummary: String {
        let hops = response.redirects.map { "\($0.statusCode) \($0.url?.absoluteString ?? "") → \($0.location ?? "")" }
        return (hops + ["最终：\(response.url?.absoluteString ?? "")"]).joined(separator: "\n")
    }
}

private struct TimingsView: View {
    let response: HTTPResponse

    var body: some View {
        let timings = response.timings
        let phases: [(String, TimeInterval?)] = [
            ("DNS 解析", timings?.dnsLookup),
            ("TCP 连接", timings?.tcpConnect),
            ("TLS 握手", timings?.tlsHandshake),
            ("发送请求", timings?.requestSent),
            ("等待响应 (TTFB)", timings?.waiting),
            ("下载内容", timings?.download),
        ]
        let total = max(response.duration, 0.000_1)
        VStack(alignment: .leading, spacing: 8) {
            Text("耗时明细").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                ForEach(Array(response.redirects.enumerated()), id: \.offset) { _, hop in
                    GridRow {
                        Text("\(hop.statusCode) 重定向").foregroundStyle(.secondary)
                        Text(hop.url?.absoluteString ?? "")
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(width: 140, alignment: .leading)
                            .help("\(hop.url?.absoluteString ?? "") → \(hop.location ?? "")")
                        Text(hop.duration.map(Formatters.duration) ?? "—")
                            .monospacedDigit()
                            .frame(minWidth: 60, alignment: .trailing)
                    }
                }
                if !response.redirects.isEmpty {
                    GridRow {
                        Text("最终请求").font(.callout.weight(.semibold))
                        Text(response.url?.absoluteString ?? "")
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(width: 140, alignment: .leading)
                        Color.clear.frame(width: 1, height: 1)
                    }
                }
                ForEach(phases, id: \.0) { name, value in
                    GridRow {
                        Text(name).foregroundStyle(.secondary)
                        GeometryReader { proxy in
                            Capsule()
                                .fill(Color.accentColor.opacity(value == nil ? 0.15 : 0.8))
                                .frame(width: max(2, proxy.size.width * CGFloat((value ?? 0) / total)))
                        }
                        .frame(width: 140, height: 6)
                        Text(value.map(Formatters.duration) ?? "—")
                            .monospacedDigit()
                            .frame(minWidth: 60, alignment: .trailing)
                    }
                }
                Divider().gridCellUnsizedAxes(.horizontal)
                GridRow {
                    Text("总计").bold()
                    Color.clear.frame(width: 140, height: 1)
                    Text(Formatters.duration(response.duration)).bold().monospacedDigit()
                        .frame(minWidth: 60, alignment: .trailing)
                }
            }
            if timings?.isReusedConnection == true {
                Text("复用了已建立的连接（keep-alive），因此没有 DNS / TCP / TLS 阶段。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !response.redirects.isEmpty {
                Text("总计包含 \(response.redirects.count) 次重定向。curl 默认不跟随重定向，如需对比请用 curl -L，或在请求的 Settings 中关闭「自动跟随重定向」。")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(width: 380)
    }
}

private struct IndexedHeader: Identifiable {
    let id: Int
    let name: String
    let value: String
}

private struct HeadersTable: View {
    let headers: [HeaderField]

    var body: some View {
        let rows = headers.enumerated().map { IndexedHeader(id: $0.offset, name: $0.element.name, value: $0.element.value) }
        Table(rows) {
            TableColumn("名称") { row in
                Text(row.name).fontWeight(.medium).textSelection(.enabled)
            }
            .width(min: 120, ideal: 220, max: 360)
            TableColumn("值") { row in
                Text(row.value).textSelection(.enabled).lineLimit(nil)
            }
        }
        .font(.system(size: 12, design: .monospaced))
        .contextMenu(forSelectionType: Int.self) { selection in
            Button("复制") {
                let text = rows.filter { selection.contains($0.id) }.map { "\($0.name): \($0.value)" }.joined(separator: "\n")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        }
    }
}

private struct CookiesTable: View {
    let cookies: [ResponseCookie]

    var body: some View {
        if cookies.isEmpty {
            ContentUnavailableView("没有 Cookie", systemImage: "circle.dashed", description: Text("响应中没有 Set-Cookie 头。"))
        } else {
            Table(cookies) {
                TableColumn("名称") { Text($0.name).textSelection(.enabled) }
                TableColumn("值") { Text($0.value).textSelection(.enabled) }
                TableColumn("Domain") { Text($0.domain) }
                TableColumn("Path") { Text($0.path) }
                TableColumn("Expires") { cookie in
                    Text(cookie.expires.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Session")
                }
                TableColumn("HttpOnly") { Text($0.isHTTPOnly ? "✓" : "") }.width(60)
                TableColumn("Secure") { Text($0.isSecure ? "✓" : "") }.width(50)
            }
            .font(.system(size: 12, design: .monospaced))
        }
    }
}
