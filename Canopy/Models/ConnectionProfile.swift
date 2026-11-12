import Foundation

/// Transport protocol used to reach the broker.
enum MQTTTransport: String, Codable, CaseIterable, Identifiable {
    case mqtt
    case mqtts
    case ws
    case wss

    var id: String { rawValue }

    var scheme: String { "\(rawValue)://" }

    var usesTLS: Bool { self == .mqtts || self == .wss }

    var usesWebSocket: Bool { self == .ws || self == .wss }

    var defaultPort: Int {
        switch self {
        case .mqtt: 1883
        case .mqtts: 8883
        case .ws: 80
        case .wss: 443
        }
    }
}

enum MQTTProtocolVersion: String, Codable, CaseIterable, Identifiable {
    case v311 = "3.1.1"
    case v5 = "5.0"

    var id: String { rawValue }
    var label: String { "MQTT \(rawValue)" }
}

enum QoSLevel: Int, Codable, CaseIterable, Identifiable {
    case atMostOnce = 0
    case atLeastOnce = 1
    case exactlyOnce = 2

    var id: Int { rawValue }
    var label: String { "QoS \(rawValue)" }
}

struct TopicSubscription: Codable, Hashable, Identifiable {
    var id = UUID()
    var topic: String
    var qos: QoSLevel = .atMostOnce
}

/// A certificate file imported by the user. The content is stored, not the path,
/// so the sandboxed app does not need persistent file access.
struct ImportedFile: Codable, Hashable {
    var fileName: String
    var data: Data
}

/// A saved broker configuration ("Favorit").
/// Secrets (password, client private key) are not encoded here; they are kept
/// in the Keychain (see `ConnectionStore`).
struct ConnectionProfile: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String = "Neue Verbindung"
    var protocolVersion: MQTTProtocolVersion = .v311
    var transport: MQTTTransport = .mqtt
    var host: String = "localhost"
    var port: Int = 1883
    var basePath: String = "/mqtt"
    var username: String = ""
    var password: String = ""
    var clientID: String = ConnectionProfile.randomClientID()
    var keepAlive: Int = 60
    var cleanSession: Bool = true
    var validateCertificate: Bool = true
    /// Additional CA certificate(s) (PEM bundle or DER) to trust for the server.
    var caCertificate: ImportedFile?
    /// Client certificate for mutual TLS (PEM or DER, optionally with intermediates).
    var clientCertificate: ImportedFile?
    /// File name of the client private key; the key itself lives in the Keychain.
    var clientKeyFileName: String?
    /// Client private key (RSA, PEM PKCS#1 or unencrypted PKCS#8). Not encoded.
    var clientKey: Data?
    var subscriptions: [TopicSubscription] = [
        TopicSubscription(topic: "#"),
        TopicSubscription(topic: "$SYS/#"),
    ]

    init() {}

    static func randomClientID() -> String {
        "canopy_" + UUID().uuidString.prefix(8).lowercased()
    }

    /// Human readable URL, e.g. `mqtts://broker.example.com:8883`.
    var displayURL: String {
        var url = "\(transport.scheme)\(host):\(port)"
        if transport.usesWebSocket { url += normalizedBasePath }
        return url
    }

    var normalizedBasePath: String {
        let trimmed = basePath.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "" }
        return trimmed.hasPrefix("/") ? trimmed : "/" + trimmed
    }

    var usesClientCertificate: Bool { clientCertificate != nil || clientKey != nil }

    var validationError: String? {
        if host.trimmingCharacters(in: .whitespaces).isEmpty { return "Host fehlt" }
        if !(1...65535).contains(port) { return "Ungültiger Port" }
        if clientID.trimmingCharacters(in: .whitespaces).isEmpty { return "Client-ID fehlt" }
        if subscriptions.allSatisfy({ $0.topic.trimmingCharacters(in: .whitespaces).isEmpty }) {
            return "Mindestens ein Topic abonnieren"
        }
        if transport.usesTLS && (clientCertificate == nil) != (clientKey == nil) {
            return "Für mTLS werden Client-Zertifikat und privater Schlüssel benötigt"
        }
        return nil
    }

    // MARK: Codable (secrets excluded, missing keys fall back to defaults)

    enum CodingKeys: String, CodingKey {
        case id, name, protocolVersion, transport, host, port, basePath, username, clientID,
             keepAlive, cleanSession, validateCertificate, caCertificate, clientCertificate,
             clientKeyFileName, subscriptions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ConnectionProfile()
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? defaults.name
        protocolVersion = try c.decodeIfPresent(MQTTProtocolVersion.self, forKey: .protocolVersion) ?? defaults.protocolVersion
        transport = try c.decodeIfPresent(MQTTTransport.self, forKey: .transport) ?? defaults.transport
        host = try c.decodeIfPresent(String.self, forKey: .host) ?? defaults.host
        port = try c.decodeIfPresent(Int.self, forKey: .port) ?? transport.defaultPort
        basePath = try c.decodeIfPresent(String.self, forKey: .basePath) ?? defaults.basePath
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        clientID = try c.decodeIfPresent(String.self, forKey: .clientID) ?? defaults.clientID
        keepAlive = try c.decodeIfPresent(Int.self, forKey: .keepAlive) ?? defaults.keepAlive
        cleanSession = try c.decodeIfPresent(Bool.self, forKey: .cleanSession) ?? defaults.cleanSession
        validateCertificate = try c.decodeIfPresent(Bool.self, forKey: .validateCertificate) ?? true
        caCertificate = try c.decodeIfPresent(ImportedFile.self, forKey: .caCertificate)
        clientCertificate = try c.decodeIfPresent(ImportedFile.self, forKey: .clientCertificate)
        clientKeyFileName = try c.decodeIfPresent(String.self, forKey: .clientKeyFileName)
        subscriptions = try c.decodeIfPresent([TopicSubscription].self, forKey: .subscriptions) ?? defaults.subscriptions
    }
}
