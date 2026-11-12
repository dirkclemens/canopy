import SwiftUI
import AppKit

enum DetailTab: String, CaseIterable, Identifiable {
    case payload = "Payload"
    case chart = "Diagramm"
    case diff = "Vergleich"

    var id: String { rawValue }
}

/// Shows the payload of the selected topic in different formats, plus history,
/// a chart of numeric values and a diff between two messages.
struct MessageDetailView: View {
    let node: TopicNode?

    @AppStorage("payloadFormat") private var formatRaw = PayloadFormat.auto.rawValue
    @AppStorage("detailTab") private var tabRaw = DetailTab.payload.rawValue
    @State private var selectedHistory: Set<UUID> = []

    private var format: PayloadFormat { PayloadFormat(rawValue: formatRaw) ?? .auto }
    private var tab: DetailTab { DetailTab(rawValue: tabRaw) ?? .payload }

    var body: some View {
        if let node, let latest = node.lastMessage {
            let selected = node.history.filter { selectedHistory.contains($0.id) }
            let message = selected.first ?? latest
            VStack(alignment: .leading, spacing: 0) {
                header(node: node, message: message)
                Divider()
                if node.history.count > 1 {
                    // Payload and history share the remaining height; the divider is draggable.
                    RatioSplitView(autosaveName: "detail", axis: .vertical, defaultRatio: 0.65,
                                   minFirst: Self.minContentHeight, minSecond: Self.minHistoryHeight) {
                        content(node: node, message: message, selected: selected)
                    } second: {
                        history(node)
                    }
                } else {
                    content(node: node, message: message, selected: selected)
                        .frame(minHeight: Self.minContentHeight)
                }
            }
            .onChange(of: node.fullTopic) { selectedHistory = [] }
        } else if let node {
            ContentUnavailableView("Keine Nachricht auf „\(node.fullTopic)“",
                                   systemImage: "tray",
                                   description: Text("Dieser Knoten gruppiert nur Untertopics."))
        } else {
            ContentUnavailableView("Kein Topic ausgewählt",
                                   systemImage: "list.bullet.indent",
                                   description: Text("Wähle links ein Topic, um die Payload anzuzeigen."))
        }
    }

    // MARK: Layout

    /// At least four lines of the monospaced payload font plus the text padding.
    static let minContentHeight: CGFloat = {
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let lineHeight = NSLayoutManager().defaultLineHeight(for: font)
        return ceil(lineHeight * 4) + 24
    }()

    /// Title row plus about two entries.
    static let minHistoryHeight: CGFloat = 70

    // MARK: Sections

    @ViewBuilder
    private func content(node: TopicNode, message: ReceivedMessage, selected: [ReceivedMessage]) -> some View {
        switch tab {
        case .payload:
            PayloadContentView(message: message, format: format)
        case .chart:
            TopicChartView(messages: node.history)
        case .diff:
            diffContent(node: node, selected: selected)
        }
    }

    private func header(node: TopicNode, message: ReceivedMessage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(node.fullTopic)
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .textSelection(.enabled)
                    .lineLimit(2)
                Spacer()
                Button {
                    Pasteboard.copy(node.fullTopic)
                } label: {
                    Label("Topic kopieren", systemImage: "doc.on.doc")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Topic kopieren")
            }
            HStack(spacing: 14) {
                metadata("Typ", PayloadFormatter.detect(message.payload).rawValue)
                metadata("QoS", "\(message.qos.rawValue)")
                metadata("Retained", message.retained ? "ja" : "nein")
                metadata("Größe", PayloadFormatter.byteCountString(message.size))
                metadata("Empfangen", message.receivedAt.formatted(date: .omitted, time: .standard))
                metadata("Anzahl", "\(node.messageCount)")
            }
            if let properties = message.properties, !properties.isEmpty {
                PropertiesView(properties: properties)
            }
            VStack(alignment: .leading) {
                HStack(alignment: .top){
                    Picker("Ansicht", selection: $tabRaw) {
                        ForEach(DetailTab.allCases) { Text($0.rawValue).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    if tab != .chart {
                        Picker("Format", selection: $formatRaw) {
                            ForEach(PayloadFormat.allCases) { Text($0.rawValue).tag($0.rawValue) }
                        }
                        .pickerStyle(.menu)
                        .fixedSize()
                        if format == .auto {
                            Text("→ \(PayloadFormatter.autoFormat(for: message.payload).rawValue)")
                                .foregroundStyle(.secondary)
                                .font(.callout)
                        }
                    }
//                    Spacer()
                }
                if tab == .payload {
                    HStack(alignment: .top) {
                        Spacer()
                        Button {
                            Pasteboard.copy(PayloadFormatter.render(message.payload, as: format))
                        } label: {
                            Label("Payload kopieren", systemImage: "doc.on.clipboard")
                        }
                    }
                }
            }
        }
        .padding(12)
    }

    private func metadata(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.callout.monospacedDigit())
        }
    }

    /// Compares two selected history entries, or the latest message with its predecessor.
    @ViewBuilder
    private func diffContent(node: TopicNode, selected: [ReceivedMessage]) -> some View {
        let pair: (old: ReceivedMessage, new: ReceivedMessage)? = {
            if selected.count >= 2 {
                let sorted = selected.sorted { $0.receivedAt < $1.receivedAt }
                return (sorted[0], sorted[sorted.count - 1])
            }
            let newer = selected.first ?? node.history.first
            guard let newer,
                  let index = node.history.firstIndex(where: { $0.id == newer.id }),
                  index + 1 < node.history.count else { return nil }
            return (node.history[index + 1], newer)
        }()
        if let pair {
            DiffView(old: pair.old, new: pair.new, format: format)
        } else {
            ContentUnavailableView("Nichts zu vergleichen",
                                   systemImage: "arrow.left.arrow.right",
                                   description: Text("Für einen Vergleich braucht es mindestens zwei Nachrichten. Mit ⌘-Klick im Verlauf zwei Einträge wählen."))
        }
    }

    private func history(_ node: TopicNode) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Verlauf (\(node.history.count))")
                Spacer()
                if !selectedHistory.isEmpty {
                    Button("Auswahl aufheben") { selectedHistory = [] }
                        .buttonStyle(.link)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 6)
            List(node.history, selection: $selectedHistory) { message in
                HStack {
                    Text(message.receivedAt.formatted(date: .omitted, time: .standard))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text(message.preview)
                        .lineLimit(1)
                    Spacer()
                    if message.retained {
                        Image(systemName: "pin.fill").foregroundStyle(.secondary).help("Retained")
                    }
                }
                .font(.system(.caption, design: .monospaced))
                .tag(message.id)
            }
            .listStyle(.plain)
        }
        .frame(maxHeight: .infinity)
    }
}

/// The rendered payload with syntax highlighting.
struct PayloadContentView: View {
    let message: ReceivedMessage
    let format: PayloadFormat

    var body: some View {
        let resolved = format == .auto ? PayloadFormatter.autoFormat(for: message.payload) : format
        let text = PayloadFormatter.render(message.payload, as: resolved)
        ScrollView([.vertical, .horizontal]) {
            Group {
                if message.payload.isEmpty {
                    Text("(leere Payload)").foregroundStyle(.secondary)
                } else {
                    Text(SyntaxHighlighter.highlight(text, as: resolved))
                }
            }
            .font(.system(.body, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(12)
        }
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

/// MQTT 5 publish properties of a message.
struct PropertiesView: View {
    let properties: MessageProperties

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 2) {
            if let contentType = properties.contentType { row("Content-Type", contentType) }
            if let responseTopic = properties.responseTopic { row("Response-Topic", responseTopic) }
            if let correlation = properties.correlationData {
                row("Correlation-Data", String(data: correlation, encoding: .utf8) ?? PayloadFormatter.hexDump(correlation))
            }
            if let utf8 = properties.payloadIsUTF8 { row("Payload-Format", utf8 ? "UTF-8" : "binär") }
            if let expiry = properties.messageExpiryInterval { row("Ablauf", "\(expiry) s") }
            ForEach(properties.userProperties) { property in
                row(property.key, property.value, isUser: true)
            }
        }
        .font(.callout)
        .padding(8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }

    private func row(_ key: String, _ value: String, isUser: Bool = false) -> some View {
        GridRow {
            Text(key)
                .foregroundStyle(isUser ? Color.accentColor : .secondary)
                .help(isUser ? "User Property" : "MQTT 5 Property")
            Text(value)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(3)
        }
    }
}

enum Pasteboard {
    static func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
