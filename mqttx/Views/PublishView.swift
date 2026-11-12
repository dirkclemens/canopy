import SwiftUI

/// Form to publish a message on the current connection (with MQTT 5 properties when available).
struct PublishView: View {
    @Environment(MQTTClientService.self) private var service
    let defaultTopic: String

    @State private var topic = ""
    @State private var payload = ""
    @State private var qos: QoSLevel = .atMostOnce
    @State private var retained = false
    @State private var showProperties = false
    @State private var contentType = ""
    @State private var responseTopic = ""
    @State private var correlationData = ""
    @State private var userProperties: [UserProperty] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Publish").font(.headline)
                Spacer()
                Button("Ausgewähltes Topic übernehmen") { topic = defaultTopic }
                    .buttonStyle(.link)
                    .disabled(defaultTopic.isEmpty)
            }
            TextField("Topic", text: $topic, prompt: Text("z. B. home/light/set"))
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
            TextEditor(text: $payload)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                .frame(minHeight: 50)
            if service.isMQTT5 {
                DisclosureGroup("MQTT 5 Properties", isExpanded: $showProperties) {
                    propertiesEditor
                }
            }
            HStack {
                Picker("QoS", selection: $qos) {
                    ForEach(QoSLevel.allCases) { Text($0.label).tag($0) }
                }
                .fixedSize()
                Toggle("Retain", isOn: $retained)
                Button("JSON formatieren") {
                    if let pretty = PayloadFormatter.prettyJSON(Data(payload.utf8)) { payload = pretty }
                }
                .disabled(PayloadFormatter.prettyJSON(Data(payload.utf8)) == nil)
                Spacer()
                Button {
                    service.publish(topic: topic, payload: Data(payload.utf8), qos: qos, retained: retained,
                                    properties: properties)
                } label: {
                    Label("Senden", systemImage: "paperplane")
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(topic.isEmpty || topic.contains("#") || topic.contains("+") || service.state != .connected)
            }
        }
        .padding(12)
        .onAppear { if topic.isEmpty { topic = defaultTopic } }
    }

    private var propertiesEditor: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
            GridRow {
                Text("Content-Type").foregroundStyle(.secondary)
                TextField("", text: $contentType, prompt: Text("application/json"))
            }
            GridRow {
                Text("Response-Topic").foregroundStyle(.secondary)
                TextField("", text: $responseTopic)
            }
            GridRow {
                Text("Correlation-Data").foregroundStyle(.secondary)
                TextField("", text: $correlationData)
            }
            ForEach($userProperties) { $property in
                GridRow {
                    TextField("", text: $property.key, prompt: Text("Schlüssel"))
                    HStack {
                        TextField("", text: $property.value, prompt: Text("Wert"))
                        Button {
                            userProperties.removeAll { $0.id == property.id }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            GridRow {
                Button {
                    userProperties.append(UserProperty(key: "", value: ""))
                } label: {
                    Label("User Property", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .gridCellColumns(2)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(.top, 4)
    }

    private var properties: MessageProperties? {
        guard service.isMQTT5 else { return nil }
        func nonEmpty(_ string: String) -> String? { string.isEmpty ? nil : string }
        let properties = MessageProperties(
            contentType: nonEmpty(contentType),
            responseTopic: nonEmpty(responseTopic),
            correlationData: nonEmpty(correlationData).map { Data($0.utf8) },
            userProperties: userProperties.filter { !$0.key.isEmpty })
        return properties.isEmpty ? nil : properties
    }
}
