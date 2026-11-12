import Foundation
import CocoaMQTT
import CocoaMQTTWebSocket

/// Events delivered by an adapter (always on the main queue).
struct MQTTAdapterCallbacks {
    var connected: () -> Void
    var connectionRefused: (String) -> Void
    var message: (ReceivedMessage) -> Void
    var disconnected: (Error?) -> Void
}

/// Common interface over CocoaMQTT (3.1.1) and CocoaMQTT5 (5.0).
protocol MQTTClientAdapter: AnyObject {
    func connect() -> Bool
    func disconnect()
    func subscribe(_ subscriptions: [TopicSubscription])
    func publish(topic: String, payload: Data, qos: QoSLevel, retained: Bool, properties: MessageProperties?)
}

enum MQTTClientFactory {
    static func makeAdapter(for profile: ConnectionProfile, callbacks: MQTTAdapterCallbacks) throws -> MQTTClientAdapter {
        let tls = try TLSConfiguration(profile: profile)
        switch profile.protocolVersion {
        case .v311: return MQTT3Adapter(profile: profile, tls: tls, callbacks: callbacks)
        case .v5: return MQTT5Adapter(profile: profile, tls: tls, callbacks: callbacks)
        }
    }

    static func makeSocket(for profile: ConnectionProfile) -> CocoaMQTTSocketProtocol {
        if profile.transport.usesWebSocket {
            let socket = CocoaMQTTWebSocket(uri: profile.normalizedBasePath)
            socket.enableSSL = profile.transport.usesTLS
            return socket
        }
        return CocoaMQTTSocket()
    }
}

/// Resolved TLS material for a profile.
struct TLSConfiguration {
    var enabled: Bool
    var acceptAnyCertificate: Bool
    var trustedCertificates: [SecCertificate] = []
    var identity: CocoaMQTTClientIdentity?

    init(profile: ConnectionProfile) throws {
        enabled = profile.transport.usesTLS
        acceptAnyCertificate = enabled && !profile.validateCertificate
        guard enabled else { return }
        if let ca = profile.caCertificate {
            trustedCertificates = try CertificateLoader.caCertificates(for: ca)
        }
        if let certificate = profile.clientCertificate, let key = profile.clientKey {
            identity = try CertificateLoader.clientIdentity(certificate: certificate.data, key: key)
        }
    }
}

private extension QoSLevel {
    var cocoa: CocoaMQTTQoS { CocoaMQTTQoS(rawValue: UInt8(rawValue)) ?? .qos0 }
    init(_ qos: CocoaMQTTQoS) { self = QoSLevel(rawValue: Int(qos.rawValue)) ?? .atMostOnce }
}

// MARK: - MQTT 3.1.1

final class MQTT3Adapter: MQTTClientAdapter {
    private let client: CocoaMQTT

    init(profile: ConnectionProfile, tls: TLSConfiguration, callbacks: MQTTAdapterCallbacks) {
        client = CocoaMQTT(clientID: profile.clientID,
                           host: profile.host.trimmingCharacters(in: .whitespaces),
                           port: UInt16(clamping: profile.port),
                           socket: MQTTClientFactory.makeSocket(for: profile))
        client.enableSSL = tls.enabled
        client.trustedServerCertificates = tls.trustedCertificates
        client.clientIdentity = tls.identity
        if tls.acceptAnyCertificate {
            client.manuallyEvaluateTrust = true
            client.didReceiveTrust = { _, _, completion in completion(true) }
        }
        client.username = profile.username.isEmpty ? nil : profile.username
        client.password = profile.password.isEmpty ? nil : profile.password
        client.keepAlive = UInt16(clamping: profile.keepAlive)
        client.cleanSession = profile.cleanSession
        client.autoReconnect = false
        client.delegateQueue = .main

        client.didConnectAck = { _, ack in
            MainActor.assumeIsolated {
                if ack == .accept { callbacks.connected() } else { callbacks.connectionRefused(ack.description) }
            }
        }
        client.didReceiveMessage = { _, message, _ in
            let received = ReceivedMessage(topic: message.topic, payload: Data(message.payload),
                                           qos: QoSLevel(message.qos), retained: message.retained,
                                           receivedAt: Date())
            MainActor.assumeIsolated { callbacks.message(received) }
        }
        client.didDisconnect = { _, error in
            MainActor.assumeIsolated { callbacks.disconnected(error) }
        }
    }

    func connect() -> Bool { client.connect(timeout: 10) }

    func disconnect() { client.disconnect() }

    func subscribe(_ subscriptions: [TopicSubscription]) {
        let topics = subscriptions.map { ($0.topic, $0.qos.cocoa) }
        if !topics.isEmpty { client.subscribe(topics) }
    }

    func publish(topic: String, payload: Data, qos: QoSLevel, retained: Bool, properties: MessageProperties?) {
        _ = client.publish(CocoaMQTTMessage(topic: topic, payload: [UInt8](payload), qos: qos.cocoa, retained: retained))
    }
}

// MARK: - MQTT 5

final class MQTT5Adapter: MQTTClientAdapter {
    private let client: CocoaMQTT5

    init(profile: ConnectionProfile, tls: TLSConfiguration, callbacks: MQTTAdapterCallbacks) {
        client = CocoaMQTT5(clientID: profile.clientID,
                            host: profile.host.trimmingCharacters(in: .whitespaces),
                            port: UInt16(clamping: profile.port),
                            socket: MQTTClientFactory.makeSocket(for: profile))
        client.enableSSL = tls.enabled
        client.trustedServerCertificates = tls.trustedCertificates
        client.clientIdentity = tls.identity
        if tls.acceptAnyCertificate {
            client.manuallyEvaluateTrust = true
            client.didReceiveTrust = { _, _, completion in completion(true) }
        }
        client.username = profile.username.isEmpty ? nil : profile.username
        client.password = profile.password.isEmpty ? nil : profile.password
        client.keepAlive = UInt16(clamping: profile.keepAlive)
        client.cleanSession = profile.cleanSession
        client.autoReconnect = false
        client.delegateQueue = .main

        client.didConnectAck = { _, reason, _ in
            MainActor.assumeIsolated {
                if reason == .success { callbacks.connected() } else { callbacks.connectionRefused("\(reason)") }
            }
        }
        client.didReceiveMessage = { _, message, _, decoded in
            let received = ReceivedMessage(topic: message.topic, payload: Data(message.payload),
                                           qos: QoSLevel(message.qos), retained: message.retained,
                                           receivedAt: Date(),
                                           properties: decoded.map(Self.properties(from:)))
            MainActor.assumeIsolated { callbacks.message(received) }
        }
        client.didDisconnect = { _, error in
            MainActor.assumeIsolated { callbacks.disconnected(error) }
        }
    }

    func connect() -> Bool { client.connect(timeout: 10) }

    func disconnect() { client.disconnect() }

    func subscribe(_ subscriptions: [TopicSubscription]) {
        let topics = subscriptions.map { MqttSubscription(topic: $0.topic, qos: $0.qos.cocoa) }
        if !topics.isEmpty { client.subscribe(topics) }
    }

    func publish(topic: String, payload: Data, qos: QoSLevel, retained: Bool, properties: MessageProperties?) {
        let message = CocoaMQTT5Message(topic: topic, payload: [UInt8](payload), qos: qos.cocoa, retained: retained)
        let publishProperties = MqttPublishProperties()
        if let properties {
            publishProperties.contentType = properties.contentType
            publishProperties.responseTopic = properties.responseTopic
            publishProperties.correlationData = properties.correlationData.map { [UInt8]($0) }
            publishProperties.messageExpiryInterval = properties.messageExpiryInterval
            publishProperties.userProperties = properties.userProperties
                .filter { !$0.key.isEmpty }
                .map { CocoaMQTTUserProperty(key: $0.key, value: $0.value) }
        }
        _ = client.publish(message, retained: retained, properties: publishProperties)
    }

    nonisolated private static func properties(from decoded: MqttDecodePublish) -> MessageProperties {
        var userProperties = decoded.userProperties.map { UserProperty(key: $0.key, value: $0.value) }
        if userProperties.isEmpty, let legacy = decoded.userProperty {
            userProperties = legacy.sorted { $0.key < $1.key }.map { UserProperty(key: $0.key, value: $0.value) }
        }
        return MessageProperties(
            contentType: decoded.contentType,
            responseTopic: decoded.responseTopic,
            correlationData: decoded.correlationData.map { Data($0) },
            payloadIsUTF8: decoded.payloadFormatIndicator.map { $0 == .utf8 },
            messageExpiryInterval: decoded.messageExpiryInterval,
            userProperties: userProperties)
    }
}
