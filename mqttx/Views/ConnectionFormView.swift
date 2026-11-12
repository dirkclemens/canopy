import SwiftUI
import UniformTypeIdentifiers

/// Form to configure a broker connection.
struct ConnectionFormView: View {
    @Binding var profile: ConnectionProfile
    let isSaved: Bool
    let onSave: () -> Void
    let onConnect: () -> Void
    let onDelete: () -> Void

    @State private var showPassword = false
    @State private var importTarget: CertificateSlot?
    @State private var importError: String?

    enum CertificateSlot {
        case ca, clientCertificate, clientKey
    }

    var body: some View {
        Form {
            Section("Verbindung") {
                TextField("Name", text: $profile.name)

                Picker("MQTT-Version", selection: $profile.protocolVersion) {
                    ForEach(MQTTProtocolVersion.allCases) { Text($0.label).tag($0) }
                }

                Picker("Protokoll", selection: transportBinding) {
                    ForEach(MQTTTransport.allCases) { transport in
                        Text(transport.scheme).tag(transport)
                    }
                }

                TextField("Host", text: $profile.host, prompt: Text("broker.example.com"))
                    .autocorrectionDisabled()

                TextField("Port", value: $profile.port, format: .number.grouping(.never))

                if profile.transport.usesWebSocket {
                    TextField("Pfad", text: $profile.basePath, prompt: Text("/mqtt"))
                }

                LabeledContent("URL") {
                    Text(profile.displayURL)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section("Authentifizierung") {
                TextField("Benutzername", text: $profile.username)
                    .autocorrectionDisabled()
                HStack {
                    if showPassword {
                        TextField("Passwort", text: $profile.password)
                    } else {
                        SecureField("Passwort", text: $profile.password)
                    }
                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .help(showPassword ? "Passwort verbergen" : "Passwort anzeigen")
                }
            }

            Section {
                Toggle("TLS verwenden", isOn: tlsBinding)
                Toggle("Server-Zertifikat prüfen", isOn: $profile.validateCertificate)
                    .disabled(!profile.transport.usesTLS)
                if profile.transport.usesTLS && !profile.validateCertificate {
                    Label("Unsicher: jedes Zertifikat wird akzeptiert (z. B. selbstsigniert).",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
                if profile.transport.usesTLS {
                    certificateRow("CA-Zertifikat", fileName: profile.caCertificate?.fileName,
                                   detail: profile.caCertificate.flatMap { CertificateLoader.summary(of: $0.data) },
                                   slot: .ca) { profile.caCertificate = nil }
                    certificateRow("Client-Zertifikat", fileName: profile.clientCertificate?.fileName,
                                   detail: profile.clientCertificate.flatMap { CertificateLoader.summary(of: $0.data) },
                                   slot: .clientCertificate) { profile.clientCertificate = nil }
                    certificateRow("Privater Schlüssel",
                                   fileName: profile.clientKey == nil ? nil : (profile.clientKeyFileName ?? "gespeichert"),
                                   detail: profile.clientKey == nil ? nil : "im Schlüsselbund",
                                   slot: .clientKey) {
                        profile.clientKey = nil
                        profile.clientKeyFileName = nil
                    }
                    if let importError {
                        Label(importError, systemImage: "xmark.octagon")
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }
            } header: {
                Text("Verschlüsselung (TLS)")
            } footer: {
                if profile.transport.usesTLS {
                    Text("Zertifikate als PEM oder DER. Privater Schlüssel: RSA im PEM-Format (PKCS#1 oder unverschlüsseltes PKCS#8). Der Dateiinhalt wird übernommen, der Schlüssel im Schlüsselbund gespeichert.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Erweitert") {
                HStack {
                    TextField("Client-ID", text: $profile.clientID)
                        .autocorrectionDisabled()
                    Button {
                        profile.clientID = ConnectionProfile.randomClientID()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Neue Client-ID erzeugen")
                }
                TextField("Keep-Alive (s)", value: $profile.keepAlive, format: .number.grouping(.never))
                Toggle("Clean Session", isOn: $profile.cleanSession)
            }

            Section {
                ForEach($profile.subscriptions) { $subscription in
                    HStack {
                        TextField("Topic", text: $subscription.topic, prompt: Text("z. B. home/#"))
                            .labelsHidden()
                            .autocorrectionDisabled()
                        Picker("QoS", selection: $subscription.qos) {
                            ForEach(QoSLevel.allCases) { Text($0.label).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        Button {
                            profile.subscriptions.removeAll { $0.id == subscription.id }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Abonnement entfernen")
                    }
                }
                Button {
                    profile.subscriptions.append(TopicSubscription(topic: ""))
                } label: {
                    Label("Topic hinzufügen", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            } header: {
                Text("Abonnements")
            } footer: {
                Text("Wildcards: `+` für eine Ebene, `#` für alle darunterliegenden Ebenen.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: Binding(get: { importTarget != nil }, set: { if !$0 { importTarget = nil } }),
                      allowedContentTypes: [.item]) { result in
            handleImport(result)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if isSaved {
                    Button(role: .destructive, action: onDelete) {
                        Label("Löschen", systemImage: "trash")
                    }
                }
                Button(action: onSave) {
                    Label("Speichern", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut("s")
                Button(action: onConnect) {
                    Label("Verbinden", systemImage: "bolt.horizontal")
                }
                .keyboardShortcut(.return)
                .disabled(profile.validationError != nil)
                .help(profile.validationError ?? "Speichern und verbinden")
            }
        }
    }

    private func certificateRow(_ title: String, fileName: String?, detail: String?,
                                slot: CertificateSlot, remove: @escaping () -> Void) -> some View {
        LabeledContent(title) {
            HStack {
                if let fileName {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(fileName).lineLimit(1)
                        if let detail {
                            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Button(role: .destructive, action: remove) {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .help("Entfernen")
                } else {
                    Text("keins").foregroundStyle(.secondary)
                }
                Button("Wählen …") {
                    importError = nil
                    importTarget = slot
                }
            }
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        guard let slot = importTarget else { return }
        importTarget = nil
        do {
            let url = try result.get()
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let file = ImportedFile(fileName: url.lastPathComponent, data: data)
            switch slot {
            case .ca:
                guard !CertificateLoader.certificates(from: data).isEmpty else {
                    importError = "„\(file.fileName)“ enthält kein gültiges Zertifikat."
                    return
                }
                profile.caCertificate = file
            case .clientCertificate:
                guard !CertificateLoader.certificates(from: data).isEmpty else {
                    importError = "„\(file.fileName)“ enthält kein gültiges Zertifikat."
                    return
                }
                profile.clientCertificate = file
            case .clientKey:
                guard String(data: data, encoding: .utf8)?.contains("PRIVATE KEY-----") == true else {
                    importError = "„\(file.fileName)“ enthält keinen PEM-Schlüssel."
                    return
                }
                profile.clientKey = data
                profile.clientKeyFileName = file.fileName
            }
            if let certificate = profile.clientCertificate, let key = profile.clientKey {
                do {
                    _ = try CertificateLoader.clientIdentity(certificate: certificate.data, key: key)
                } catch {
                    importError = error.localizedDescription
                }
            }
        } catch {
            importError = error.localizedDescription
        }
    }

    /// Switching the protocol also updates the port if it was still the old default.
    private var transportBinding: Binding<MQTTTransport> {
        Binding {
            profile.transport
        } set: { newValue in
            if profile.port == profile.transport.defaultPort {
                profile.port = newValue.defaultPort
            }
            profile.transport = newValue
        }
    }

    private var tlsBinding: Binding<Bool> {
        Binding {
            profile.transport.usesTLS
        } set: { useTLS in
            let target: MQTTTransport = switch (profile.transport.usesWebSocket, useTLS) {
            case (false, false): .mqtt
            case (false, true): .mqtts
            case (true, false): .ws
            case (true, true): .wss
            }
            transportBinding.wrappedValue = target
        }
    }
}
