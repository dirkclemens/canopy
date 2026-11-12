import SwiftUI
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable {
    case json = "JSON"
    case csv = "CSV"

    var id: String { rawValue }
    var contentType: UTType { self == .json ? .json : .commaSeparatedText }
}

/// Serialises received messages to JSON or CSV.
enum MessageExporter {

    static func export(_ messages: [ReceivedMessage], as format: ExportFormat) -> Data {
        switch format {
        case .json: json(messages)
        case .csv: Data(csv(messages).utf8)
        }
    }

    static func json(_ messages: [ReceivedMessage]) -> Data {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let entries: [[String: Any]] = messages.map { message in
            var entry: [String: Any] = [
                "topic": message.topic,
                "timestamp": formatter.string(from: message.receivedAt),
                "qos": message.qos.rawValue,
                "retained": message.retained,
            ]
            if let text = message.text {
                entry["payload"] = text
            } else {
                entry["payloadBase64"] = message.payload.base64EncodedString()
            }
            if let properties = message.properties, !properties.isEmpty {
                var props: [String: Any] = [:]
                props["contentType"] = properties.contentType
                props["responseTopic"] = properties.responseTopic
                props["correlationData"] = properties.correlationData?.base64EncodedString()
                props["messageExpiryInterval"] = properties.messageExpiryInterval
                if !properties.userProperties.isEmpty {
                    props["userProperties"] = properties.userProperties.map { ["key": $0.key, "value": $0.value] }
                }
                entry["properties"] = props
            }
            return entry
        }
        return (try? JSONSerialization.data(withJSONObject: entries,
                                            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data()
    }

    static func csv(_ messages: [ReceivedMessage]) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var lines = ["timestamp,topic,qos,retained,payload"]
        for message in messages {
            let payload = message.text ?? "base64:" + message.payload.base64EncodedString()
            lines.append([
                formatter.string(from: message.receivedAt),
                escape(message.topic),
                String(message.qos.rawValue),
                message.retained ? "true" : "false",
                escape(payload),
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// RFC 4180 quoting.
    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

/// Document wrapper for `.fileExporter`. The format is chosen in the save panel
/// (JSON or CSV) and the content is generated for that type when writing.
struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [] }
    static var writableContentTypes: [UTType] { [.json, .commaSeparatedText] }

    var messages: [ReceivedMessage]

    init(messages: [ReceivedMessage]) { self.messages = messages }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.fileReadUnsupportedScheme)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let format: ExportFormat = configuration.contentType.conforms(to: .commaSeparatedText) ? .csv : .json
        return FileWrapper(regularFileWithContents: MessageExporter.export(messages, as: format))
    }
}
