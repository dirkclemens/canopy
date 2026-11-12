import Foundation

struct UserProperty: Hashable, Codable, Identifiable {
    var id = UUID()
    var key: String
    var value: String
}

/// MQTT 5 publish properties (all optional).
struct MessageProperties: Hashable, Codable {
    var contentType: String?
    var responseTopic: String?
    var correlationData: Data?
    var payloadIsUTF8: Bool?
    var messageExpiryInterval: UInt32?
    var userProperties: [UserProperty] = []

    var isEmpty: Bool {
        contentType == nil && responseTopic == nil && correlationData == nil
            && payloadIsUTF8 == nil && messageExpiryInterval == nil && userProperties.isEmpty
    }
}

struct ReceivedMessage: Identifiable, Hashable {
    let id = UUID()
    let topic: String
    let payload: Data
    let qos: QoSLevel
    let retained: Bool
    let receivedAt: Date
    var properties: MessageProperties? = nil

    var size: Int { payload.count }

    /// Payload as UTF-8 text, if it is valid UTF-8.
    var text: String? { String(data: payload, encoding: .utf8) }

    /// Numeric value of the payload, if it is a plain number.
    var numericValue: Double? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = Double(trimmed) { return value }
        switch trimmed.lowercased() {
        case "true", "on": return 1
        case "false", "off": return 0
        default: return nil
        }
    }

    /// Short single line preview for the tree.
    var preview: String {
        guard let text else { return "<\(payload.count) Bytes binär>" }
        let line = text.replacingOccurrences(of: "\n", with: " ")
        return line.count > 80 ? String(line.prefix(80)) + "…" : line
    }
}
