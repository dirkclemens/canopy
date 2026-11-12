import Foundation

/// The ways a payload can be rendered in the detail view.
enum PayloadFormat: String, CaseIterable, Identifiable {
    case auto = "Automatisch"
    case raw = "Raw / Text"
    case json = "JSON"
    case xml = "XML"
    case hex = "Hex"
    case base64 = "Base64"
    case binary = "Binär"
    case decimal = "Dezimal"

    var id: String { rawValue }
}

/// Detected content type of a payload.
enum PayloadKind: String {
    case empty = "Leer"
    case json = "JSON"
    case xml = "XML"
    case number = "Zahl"
    case text = "Text"
    case binary = "Binär"
}

enum PayloadFormatter {

    static func detect(_ data: Data) -> PayloadKind {
        if data.isEmpty { return .empty }
        guard let text = String(data: data, encoding: .utf8) else { return .binary }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if Double(trimmed) != nil { return .number }
        if (trimmed.hasPrefix("{") || trimmed.hasPrefix("[")),
           (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil {
            return .json
        }
        if trimmed.hasPrefix("<"), (try? XMLDocument(data: data, options: [])) != nil {
            return .xml
        }
        if text.unicodeScalars.contains(where: { $0.properties.generalCategory == .control && !"\n\r\t".unicodeScalars.contains($0) }) {
            return .binary
        }
        return .text
    }

    /// Format to use when the user selected `.auto`.
    static func autoFormat(for data: Data) -> PayloadFormat {
        switch detect(data) {
        case .json: .json
        case .xml: .xml
        case .binary: .hex
        case .empty, .number, .text: .raw
        }
    }

    /// Renders `data` in the requested format. Returns an error description in the
    /// text when the payload cannot be represented in that format.
    static func render(_ data: Data, as format: PayloadFormat) -> String {
        switch format {
        case .auto: render(data, as: autoFormat(for: data))
        case .raw: rawText(data)
        case .json: prettyJSON(data) ?? "⚠︎ Kein gültiges JSON\n\n" + rawText(data)
        case .xml: prettyXML(data) ?? "⚠︎ Kein gültiges XML\n\n" + rawText(data)
        case .hex: hexDump(data)
        case .base64: data.base64EncodedString(options: [.lineLength76Characters, .endLineWithLineFeed])
        case .binary: data.map { byte in
                let bits = String(byte, radix: 2)
                return String(repeating: "0", count: 8 - bits.count) + bits
            }.chunked(8).map { $0.joined(separator: " ") }.joined(separator: "\n")
        case .decimal: data.map(String.init).chunked(16).map { $0.joined(separator: " ") }.joined(separator: "\n")
        }
    }

    static func rawText(_ data: Data) -> String {
        if let text = String(data: data, encoding: .utf8) { return text }
        // Fall back to Latin-1 so arbitrary bytes are at least visible.
        return String(data: data, encoding: .isoLatin1) ?? ""
    }

    static func prettyJSON(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let pretty = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed])
        else { return nil }
        return String(data: pretty, encoding: .utf8)
    }

    static func prettyXML(_ data: Data) -> String? {
        guard let document = try? XMLDocument(data: data, options: [.nodePreserveWhitespace]) else { return nil }
        return document.xmlString(options: [.nodePrettyPrint])
    }

    /// Classic hex dump: offset, 16 bytes in hex, ASCII column.
    static func hexDump(_ data: Data) -> String {
        let bytes = [UInt8](data)
        var lines: [String] = []
        var offset = 0
        while offset < bytes.count {
            let chunk = bytes[offset..<min(offset + 16, bytes.count)]
            var hex = chunk.map { String(format: "%02x", $0) }
            while hex.count < 16 { hex.append("  ") }
            let left = hex[0..<8].joined(separator: " ")
            let right = hex[8..<16].joined(separator: " ")
            let ascii = chunk.map { (0x20...0x7e).contains($0) ? String(UnicodeScalar($0)) : "." }.joined()
            lines.append(String(format: "%08x  ", offset) + left + "  " + right + "  |" + ascii + "|")
            offset += 16
        }
        return lines.joined(separator: "\n")
    }

    static func byteCountString(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .binary)
    }
}

private extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
