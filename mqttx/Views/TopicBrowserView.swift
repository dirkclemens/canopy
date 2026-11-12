import SwiftUI

/// Connected view: topic tree on the left, message details on the right.
struct TopicBrowserView: View {
    @Environment(MQTTClientService.self) private var service
    @State private var selectedTopic: String?
    @State private var filter = ""
    @State private var exportDocument: ExportDocument?
    @State private var exportName = "mqtt-export"
    @State private var retainedToDelete: [String] = []
    @State private var revealTopic: String?

    var body: some View {
        RatioSplitView(autosaveName: "topicBrowser", defaultRatio: 0.4, minLeft: 280, minRight: 380) {
            VStack(spacing: 0) {
                ConnectionStatusView()
                Divider()
                TopicTreeView(selection: $selectedTopic, reveal: $revealTopic, filter: filter,
                              onExport: export,
                              onDeleteRetained: { retainedToDelete = $0.retainedTopics })
            }
        } right: {
            // Pure SwiftUI split: AppKit's VSplitView did not respect the toolbar's
            // safe area, so the top of the detail view could end up under the toolbar.
            RatioSplitView(autosaveName: "publish", axis: .vertical, defaultRatio: 0.7,
                           minFirst: 330, minSecond: 160) {
                MessageDetailView(node: selectedTopic.flatMap { service.root.node(forTopic: $0) })
            } second: {
                PublishView(defaultTopic: selectedTopic ?? "")
            }
        }
        .onAppear(perform: restoreSelection)
        .onChange(of: service.state) { old, new in
            // Reconnect: the tree was cleared, reveal the selection again once it reappears.
            if new == .connecting, old != .connecting { revealTopic = selectedTopic }
        }
        .onChange(of: selectedTopic) { _, topic in
            if let topic { SelectionStore.save(topic, for: service.profile?.id) }
        }
        .searchable(text: $filter, placement: .toolbar, prompt: "Topics filtern")
        .fileExporter(isPresented: Binding(get: { exportDocument != nil }, set: { if !$0 { exportDocument = nil } }),
                      document: exportDocument,
                      contentTypes: ExportDocument.writableContentTypes,
                      defaultFilename: exportName) { _ in
            exportDocument = nil
        }
        .confirmationDialog(retainedToDelete.count == 1
                                ? "Retained-Nachricht auf „\(retainedToDelete[0])“ löschen?"
                                : "\(retainedToDelete.count) Retained-Nachrichten löschen?",
                            isPresented: Binding(get: { !retainedToDelete.isEmpty },
                                                 set: { if !$0 { retainedToDelete = [] } })) {
            Button("Löschen", role: .destructive) {
                service.deleteRetained(topics: retainedToDelete)
                retainedToDelete = []
            }
        } message: {
            Text("Es wird eine leere Retained-Nachricht an jedes Topic gesendet. Das kann nicht rückgängig gemacht werden.")
        }
        .navigationTitle(service.profile?.name ?? "mqttX")
        .navigationSubtitle(service.profile?.displayURL ?? "")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    service.disconnect()
                } label: {
                    Label("Trennen", systemImage: "chevron.backward")
                }
                .help("Verbindung trennen und zur Übersicht zurück")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    export(service.root)
                } label: {
                    Label("Exportieren", systemImage: "square.and.arrow.up")
                }
                .help("Alle Nachrichten als JSON oder CSV exportieren")
                .disabled(service.totalMessages == 0)
                Button {
                    selectedTopic = nil
                    service.clearTree()
                } label: {
                    Label("Baum leeren", systemImage: "trash")
                }
                .help("Alle empfangenen Nachrichten verwerfen")
            }
        }
    }
}

extension TopicBrowserView {
    private func restoreSelection() {
        guard let topic = SelectionStore.topic(for: service.profile?.id) else { return }
        selectedTopic = topic
        revealTopic = topic
    }

    private func export(_ node: TopicNode) {
        let base = node.fullTopic.isEmpty ? (service.profile?.name ?? "mqtt") : node.fullTopic
        exportName = base.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ":", with: "_")
        exportDocument = ExportDocument(messages: node.allMessages)
    }
}

/// Remembers the last selected topic per saved connection.
enum SelectionStore {
    private static func key(_ id: UUID) -> String { "selectedTopic." + id.uuidString }

    static func topic(for profileID: UUID?) -> String? {
        profileID.flatMap { UserDefaults.standard.string(forKey: key($0)) }
    }

    static func save(_ topic: String, for profileID: UUID?) {
        guard let profileID else { return }
        UserDefaults.standard.set(topic, forKey: key(profileID))
    }
}

/// Status bar above the topic tree: connection state and counters, or the
/// full error message with a reconnect button.
struct ConnectionStatusView: View {
    @Environment(MQTTClientService.self) private var service

    var body: some View {
        Group {
            if case .failed(let reason) = service.state {
                failure(reason)
            } else {
                status
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .animation(.default, value: service.state)
    }

    private var status: some View {
        HStack(spacing: 6) {
            if service.state == .connecting {
                ProgressView().controlSize(.mini)
            } else {
                Circle()
                    .fill(service.state == .connected ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
            }
            Text(service.state.label)
                .lineLimit(1)
            Spacer(minLength: 8)
            if service.state == .connected {
                Text("\(service.root.subtreeTopicCount) Topics · \(service.totalMessages) Nachrichten")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
        .font(.callout)
    }

    private func failure(_ reason: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 2) {
                Text("Verbindung fehlgeschlagen")
                    .fontWeight(.semibold)
                Text(reason)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 8)
            if let profile = service.profile {
                Button("Erneut verbinden") { service.connect(profile) }
                    .controlSize(.small)
            }
        }
        .font(.callout)
    }

    private var background: Color {
        if case .failed = service.state { return Color.red.opacity(0.12) }
        return .clear
    }
}
