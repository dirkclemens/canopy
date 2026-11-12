import Foundation
import Observation

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case failed(String)

    var label: String {
        switch self {
        case .disconnected: "Getrennt"
        case .connecting: "Verbinde …"
        case .connected: "Verbunden"
        case .failed(let reason): "Fehler: \(reason)"
        }
    }

    var isActive: Bool { self == .connecting || self == .connected }
}

/// Owns one MQTT connection (one per window) and the topic tree built from its messages.
@Observable
final class MQTTClientService {
    private(set) var state: ConnectionState = .disconnected
    private(set) var profile: ConnectionProfile?
    private(set) var totalMessages = 0
    let root = TopicNode(segment: "", fullTopic: "", parent: nil)

    @ObservationIgnored private var client: MQTTClientAdapter?
    @ObservationIgnored private var connectionID = UUID()
    @ObservationIgnored private var pending: [ReceivedMessage] = []
    @ObservationIgnored private var flushScheduled = false

    var isMQTT5: Bool { profile?.protocolVersion == .v5 }

    // MARK: Connection

    func connect(_ profile: ConnectionProfile) {
        disconnect()
        self.profile = profile
        clearTree()

        // Each connection attempt gets an ID so late callbacks of an old client are ignored.
        let id = UUID()
        connectionID = id
        let callbacks = MQTTAdapterCallbacks(
            connected: { [weak self] in self?.handleConnected(id) },
            connectionRefused: { [weak self] reason in self?.handleRefused(reason, id) },
            message: { [weak self] message in self?.enqueue(message, id) },
            disconnected: { [weak self] error in self?.handleDisconnect(error, id) })

        do {
            let adapter = try MQTTClientFactory.makeAdapter(for: profile, callbacks: callbacks)
            client = adapter
            state = .connecting
            if !adapter.connect() {
                state = .failed("Verbindung konnte nicht gestartet werden")
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func disconnect() {
        connectionID = UUID()
        client?.disconnect()
        client = nil
        state = .disconnected
    }

    func clearTree() {
        pending.removeAll()
        root.removeAll()
        totalMessages = 0
    }

    // MARK: Publish

    func publish(topic: String, payload: Data, qos: QoSLevel, retained: Bool, properties: MessageProperties? = nil) {
        guard let client, state == .connected, !topic.isEmpty else { return }
        client.publish(topic: topic, payload: payload, qos: qos, retained: retained,
                       properties: isMQTT5 ? properties : nil)
    }

    /// Clears retained messages by publishing an empty retained payload to each topic.
    func deleteRetained(topics: [String]) {
        for topic in topics {
            publish(topic: topic, payload: Data(), qos: .atLeastOnce, retained: true)
        }
    }

    // MARK: Callbacks

    private func handleConnected(_ id: UUID) {
        guard id == connectionID, let profile else { return }
        state = .connected
        let subscriptions = profile.subscriptions
            .map { TopicSubscription(id: $0.id, topic: $0.topic.trimmingCharacters(in: .whitespaces), qos: $0.qos) }
            .filter { !$0.topic.isEmpty }
        client?.subscribe(subscriptions)
    }

    private func handleRefused(_ reason: String, _ id: UUID) {
        guard id == connectionID else { return }
        state = .failed("Broker lehnt ab: \(reason)")
    }

    private func handleDisconnect(_ error: Error?, _ id: UUID) {
        guard id == connectionID else { return }
        if case .failed = state { return }
        if let error {
            state = .failed(error.localizedDescription)
        } else if state == .connecting {
            state = .failed("Verbindung abgelehnt")
        } else {
            state = .failed("Verbindung getrennt")
        }
    }

    /// Messages are buffered and inserted in batches so a busy broker does not
    /// trigger a UI update per message.
    private func enqueue(_ message: ReceivedMessage, _ id: UUID) {
        guard id == connectionID else { return }
        pending.append(message)
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            MainActor.assumeIsolated { self?.flush() }
        }
    }

    private func flush() {
        flushScheduled = false
        guard !pending.isEmpty else { return }
        let batch = pending
        pending.removeAll(keepingCapacity: true)
        for message in batch {
            root.insert(message)
        }
        totalMessages += batch.count
    }
}
