import SwiftUI

/// Hierarchical display of all received topics.
struct TopicTreeView: View {
    @Environment(MQTTClientService.self) private var service
    @Binding var selection: String?
    /// Topic to scroll to and expand once it exists in the tree (e.g. restored selection).
    @Binding var reveal: String?
    let filter: String
    var onExport: (TopicNode) -> Void = { _ in }
    var onDeleteRetained: (TopicNode) -> Void = { _ in }

    var body: some View {
        Group {
            if service.root.sortedChildren.isEmpty {
                ContentUnavailableView {
                    Label(placeholderTitle, systemImage: "antenna.radiowaves.left.and.right")
                } description: {
                    if let subscriptions = service.profile?.subscriptions {
                        Text("Abonniert: " + subscriptions.map(\.topic).filter { !$0.isEmpty }.joined(separator: ", "))
                    }
                }
            } else if filter.isEmpty {
                ScrollViewReader { proxy in
                    List(selection: $selection) {
                        ForEach(service.root.sortedChildren) { node in
                            TopicTreeRow(node: node, expanded: $expanded, menu: menu(for:))
                        }
                    }
                    .onChange(of: service.totalMessages, initial: true) { revealIfPossible(proxy) }
                    .onChange(of: reveal) { revealIfPossible(proxy) }
                }
            } else {
                // Flat list of matching topics while filtering.
                List(filteredNodes, selection: $selection) { node in
                    TopicRow(node: node, showFullTopic: true)
                        .tag(node.fullTopic)
                        .contextMenu { menu(for: node) }
                }
            }
        }
        .listStyle(.sidebar)
    }

    @State private var expanded: Set<String> = []

    /// The status bar above shows details (including errors), so keep this short.
    private var placeholderTitle: String {
        switch service.state {
        case .connected: "Warte auf Nachrichten …"
        case .connecting: "Verbinde …"
        case .disconnected, .failed: "Keine Verbindung"
        }
    }

    /// Expands all ancestors of `reveal` and scrolls to it as soon as the node exists.
    private func revealIfPossible(_ proxy: ScrollViewProxy) {
        guard let topic = reveal, let node = service.root.node(forTopic: topic) else { return }
        var ancestor = node.parent
        while let current = ancestor, current.parent != nil {
            expanded.insert(current.fullTopic)
            ancestor = current.parent
        }
        reveal = nil
        if selection == nil { selection = topic }
        // Wait one runloop pass so the expanded rows exist before scrolling.
        DispatchQueue.main.async {
            withAnimation { proxy.scrollTo(topic, anchor: .center) }
        }
    }

    @ViewBuilder
    private func menu(for node: TopicNode) -> some View {
        Button("Topic kopieren") { Pasteboard.copy(node.fullTopic) }
        if let message = node.lastMessage {
            Button("Payload kopieren") { Pasteboard.copy(PayloadFormatter.rawText(message.payload)) }
        }
        Divider()
        Button("Exportieren …") { onExport(node) }
            .disabled(node.subtreeMessageCount == 0)
        Divider()
        let retained = node.retainedTopics
        Button(retained.count > 1 ? "Retained-Nachrichten löschen (\(retained.count)) …"
                                  : "Retained-Nachricht löschen …", role: .destructive) {
            onDeleteRetained(node)
        }
        .disabled(retained.isEmpty || service.state != .connected)
    }

    private var filteredNodes: [TopicNode] {
        var result: [TopicNode] = []
        func visit(_ node: TopicNode) {
            if node.lastMessage != nil,
               node.fullTopic.localizedCaseInsensitiveContains(filter)
                || (node.lastMessage?.text?.localizedCaseInsensitiveContains(filter) ?? false) {
                result.append(node)
            }
            node.sortedChildren.forEach(visit)
        }
        service.root.sortedChildren.forEach(visit)
        return result
    }
}

/// One node of the tree; recurses into its children when expanded.
private struct TopicTreeRow<Menu: View>: View {
    let node: TopicNode
    @Binding var expanded: Set<String>
    let menu: (TopicNode) -> Menu

    var body: some View {
        if node.sortedChildren.isEmpty {
            row
        } else {
            DisclosureGroup(isExpanded: isExpanded) {
                ForEach(node.sortedChildren) { child in
                    TopicTreeRow(node: child, expanded: $expanded, menu: menu)
                }
            } label: {
                row
            }
        }
    }

    private var row: some View {
        TopicRow(node: node, showFullTopic: false)
            .tag(node.fullTopic)
            .id(node.fullTopic)
            .contextMenu { menu(node) }
    }

    private var isExpanded: Binding<Bool> {
        Binding {
            expanded.contains(node.fullTopic)
        } set: { open in
            if open { expanded.insert(node.fullTopic) } else { expanded.remove(node.fullTopic) }
        }
    }
}

struct TopicRow: View {
    let node: TopicNode
    let showFullTopic: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(showFullTopic ? node.fullTopic : (node.segment.isEmpty ? "∅" : node.segment))
                .fontWeight(node.sortedChildren.isEmpty ? .regular : .semibold)
                .lineLimit(1)
                .layoutPriority(1)

            if let message = node.lastMessage {
                Text("= " + message.preview)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 4)

            if !node.sortedChildren.isEmpty {
                Text("\(node.subtreeTopicCount) Topics")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if node.subtreeMessageCount > 0 {
                Text("\(node.subtreeMessageCount)")
                    .font(.caption2.monospacedDigit())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
                    .help("Empfangene Nachrichten")
            }
        }
        .font(.system(.body, design: .monospaced))
    }
}
