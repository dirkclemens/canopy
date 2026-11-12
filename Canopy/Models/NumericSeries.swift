import Foundation

/// Extracts plottable numeric values from a topic's message history.
enum NumericSeries {
    /// Key used for payloads that are a plain number.
    static let valueKey = "Wert"

    struct Point: Identifiable {
        let id: UUID
        let date: Date
        let value: Double
    }

    /// Numeric values of one message: either the payload itself (`valueKey`) or
    /// every numeric leaf of a JSON payload, keyed by its path (e.g. `sensor.temp`, `values[0]`).
    static func values(of message: ReceivedMessage) -> [String: Double] {
        if let number = message.numericValue { return [valueKey: number] }
        guard let object = try? JSONSerialization.jsonObject(with: message.payload, options: [.fragmentsAllowed]) else {
            return [:]
        }
        var result: [String: Double] = [:]
        flatten(object, path: "", into: &result)
        return result
    }

    /// All series keys found in `messages`, sorted.
    static func keys(in messages: [ReceivedMessage]) -> [String] {
        var keys = Set<String>()
        for message in messages { keys.formUnion(values(of: message).keys) }
        return keys.sorted { lhs, rhs in
            if lhs == valueKey { return true }
            if rhs == valueKey { return false }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }

    static func points(for key: String, in messages: [ReceivedMessage]) -> [Point] {
        messages.compactMap { message in
            values(of: message)[key].map { Point(id: message.id, date: message.receivedAt, value: $0) }
        }
        .sorted { $0.date < $1.date }
    }

    private static func flatten(_ object: Any, path: String, into result: inout [String: Double]) {
        switch object {
        case let number as NSNumber:
            // JSON booleans arrive as NSNumber too; chart them as 0/1.
            result[path.isEmpty ? valueKey : path] = number.doubleValue
        case let dictionary as [String: Any]:
            for (key, value) in dictionary {
                flatten(value, path: path.isEmpty ? key : "\(path).\(key)", into: &result)
            }
        case let array as [Any]:
            for (index, value) in array.enumerated() {
                flatten(value, path: "\(path)[\(index)]", into: &result)
            }
        case let string as String:
            if let number = Double(string.trimmingCharacters(in: .whitespaces)) {
                result[path.isEmpty ? valueKey : path] = number
            }
        default:
            break
        }
    }
}
