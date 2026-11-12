import SwiftUI

/// Start screen: saved connections on the left, editable configuration on the right.
struct ConnectionManagerView: View {
    @Environment(ConnectionStore.self) private var store
    @Environment(MQTTClientService.self) private var service

    @State private var selection: UUID?
    @State private var draft = ConnectionProfile()
    @State private var confirmDelete = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Gespeicherte Verbindungen") {
                    ForEach(store.profiles) { profile in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.name).font(.headline)
                            Text(profile.displayURL)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .padding(.vertical, 2)
                        .tag(profile.id)
                        .contextMenu {
                            Button("Verbinden") { connect(profile) }
                            Button("Duplizieren") { selection = store.duplicate(profile.id)?.id }
                            Divider()
                            Button("Löschen", role: .destructive) {
                                selection = profile.id
                                confirmDelete = true
                            }
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button {
                        newProfile()
                    } label: {
                        Label("Neue Verbindung", systemImage: "plus")
                    }
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(8)
            }
        } detail: {
            ConnectionFormView(
                profile: $draft,
                isSaved: store.profile(with: draft.id) != nil,
                onSave: save,
                onConnect: { save(); connect(draft) },
                onDelete: { confirmDelete = true })
            .id(draft.id)
        }
        .navigationTitle("mqttX")
        .onAppear {
            if selection == nil { selection = store.profiles.first?.id }
            loadSelection()
        }
        .onChange(of: selection) { loadSelection() }
        .confirmationDialog("Verbindung „\(draft.name)“ löschen?",
                            isPresented: $confirmDelete) {
            Button("Löschen", role: .destructive) {
                store.delete(draft.id)
                selection = store.profiles.first?.id
                loadSelection()
            }
        }
    }

    private func loadSelection() {
        if let profile = store.profile(with: selection) {
            draft = profile
        } else if selection != nil || store.profile(with: draft.id) != nil {
            draft = ConnectionProfile()
        }
    }

    private func newProfile() {
        selection = nil
        draft = ConnectionProfile()
    }

    private func save() {
        store.save(draft)
        selection = draft.id
    }

    private func connect(_ profile: ConnectionProfile) {
        service.connect(profile)
    }
}
