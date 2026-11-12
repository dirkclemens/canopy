import Foundation
import Testing
@testable import mqttx

/// End-to-end tests against a local broker. They are skipped unless a broker
/// listens on 127.0.0.1:18830. Start it from the project directory with:
///
///     mosquitto -c mqttxTests/Fixtures/mosquitto-test.conf
///
/// Ports: 18830 plain, 18831 TLS (test CA), 18832 TLS with client certificate.
@Suite("Broker-Integration", .enabled(if: LocalBroker.isAvailable), .serialized)
struct BrokerIntegrationTests {
    static let port = LocalBroker.port

    private func profile(_ version: MQTTProtocolVersion, topic: String) -> ConnectionProfile {
        var profile = ConnectionProfile()
        profile.protocolVersion = version
        profile.host = "127.0.0.1"
        profile.port = Self.port
        profile.subscriptions = [TopicSubscription(topic: topic + "/#", qos: .atLeastOnce)]
        return profile
    }

    private func waitUntil(_ timeout: Duration = .seconds(5), _ condition: () -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    @Test(arguments: [MQTTProtocolVersion.v311, .v5])
    func publishReceiveAndDeleteRetained(version: MQTTProtocolVersion) async {
        let base = "mqttx-itest/\(UUID().uuidString.prefix(8))"
        let service = MQTTClientService()
        service.connect(profile(version, topic: base))
        #expect(await waitUntil { service.state == .connected }, "state: \(service.state)")
        try? await Task.sleep(for: .milliseconds(300))   // let SUBACK arrive

        let properties = MessageProperties(contentType: "application/json",
                                           responseTopic: "\(base)/reply",
                                           userProperties: [UserProperty(key: "source", value: "test")])
        service.publish(topic: "\(base)/sensor", payload: Data(#"{"t":21}"#.utf8),
                        qos: .atLeastOnce, retained: true, properties: properties)

        #expect(await waitUntil { service.root.node(forTopic: "\(base)/sensor")?.lastMessage != nil })
        let message = service.root.node(forTopic: "\(base)/sensor")?.lastMessage
        #expect(message?.text == #"{"t":21}"#)
        if version == .v5 {
            #expect(message?.properties?.contentType == "application/json")
            #expect(message?.properties?.responseTopic == "\(base)/reply")
            #expect(message?.properties?.userProperties.map(\.key) == ["source"])
        } else {
            #expect(message?.properties == nil)
        }

        // A second client sees the message as retained.
        let second = MQTTClientService()
        second.connect(profile(version, topic: base))
        #expect(await waitUntil { second.root.node(forTopic: "\(base)/sensor")?.lastMessage != nil })
        #expect(second.root.node(forTopic: "\(base)/sensor")?.lastMessage?.retained == true)
        let retained = second.root.retainedTopics
        #expect(retained == ["\(base)/sensor"])

        // Delete it and verify a fresh client gets nothing.
        second.deleteRetained(topics: retained)
        #expect(await waitUntil { second.root.node(forTopic: "\(base)/sensor")?.lastMessage?.payload.isEmpty == true })
        second.disconnect()

        let third = MQTTClientService()
        third.connect(profile(version, topic: base))
        #expect(await waitUntil { third.state == .connected })
        try? await Task.sleep(for: .seconds(1))
        #expect(third.root.node(forTopic: "\(base)/sensor") == nil)
        third.disconnect()
        service.disconnect()
        #expect(service.state == .disconnected)
    }

    // MARK: TLS

    private func fixture(_ name: String) throws -> Data {
        let bundle = Bundle(for: BundleToken.self)
        let url = try #require(bundle.url(forResource: name, withExtension: nil)
                               ?? bundle.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"),
                               "Fixture \(name) fehlt im Test-Bundle")
        return try Data(contentsOf: url)
    }

    private func tlsProfile(port: Int, clientCertificate: Bool) throws -> ConnectionProfile {
        var profile = profile(.v311, topic: "mqttx-itest-tls")
        profile.transport = .mqtts
        profile.port = port
        profile.caCertificate = ImportedFile(fileName: "test-ca.pem", data: try fixture("test-ca.pem"))
        if clientCertificate {
            profile.clientCertificate = ImportedFile(fileName: "test-client.pem", data: try fixture("test-client.pem"))
            profile.clientKey = try fixture("test-client.key")
        }
        return profile
    }

    @Test func tlsWithCustomCA() async throws {
        let service = MQTTClientService()
        service.connect(try tlsProfile(port: 18831, clientCertificate: false))
        #expect(await waitUntil { service.state == .connected }, "state: \(service.state)")
        service.disconnect()
    }

    @Test func tlsWithoutCAFailsValidation() async throws {
        var profile = try tlsProfile(port: 18831, clientCertificate: false)
        profile.caCertificate = nil
        let service = MQTTClientService()
        service.connect(profile)
        #expect(await waitUntil {
            if case .failed = service.state { return true }
            return false
        }, "state: \(service.state)")
        service.disconnect()
    }

    @Test func tlsAcceptingAnyCertificate() async throws {
        var profile = try tlsProfile(port: 18831, clientCertificate: false)
        profile.caCertificate = nil
        profile.validateCertificate = false
        let service = MQTTClientService()
        service.connect(profile)
        #expect(await waitUntil { service.state == .connected }, "state: \(service.state)")
        service.disconnect()
    }

    @Test func mutualTLS() async throws {
        let service = MQTTClientService()
        service.connect(try tlsProfile(port: 18832, clientCertificate: true))
        #expect(await waitUntil { service.state == .connected }, "state: \(service.state)")
        service.disconnect()
    }

    @Test func mutualTLSWithoutClientCertificateFails() async throws {
        let service = MQTTClientService()
        service.connect(try tlsProfile(port: 18832, clientCertificate: false))
        #expect(await waitUntil {
            if case .failed = service.state { return true }
            return false
        }, "state: \(service.state)")
        service.disconnect()
    }

    @Test func refusedConnectionReportsFailure() async {
        var profile = profile(.v311, topic: "x")
        profile.port = 1   // nothing listens here
        let service = MQTTClientService()
        service.connect(profile)
        #expect(await waitUntil {
            if case .failed = service.state { return true }
            return false
        })
    }
}

/// Detects the optional local test broker.
enum LocalBroker {
    static let port = 18830

    static var isAvailable: Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }
}

private final class BundleToken {}
