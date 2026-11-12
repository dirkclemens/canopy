import Foundation
import Security

/// Minimal wrapper around generic password items in the Keychain.
enum KeychainHelper {
    private static let service = "de.adcore.mqttX.connection"

    enum Item: String {
        case password = ""
        case clientKey = ".clientKey"
    }

    static func password(for id: UUID) -> String {
        data(.password, for: id).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    static func setPassword(_ password: String, for id: UUID) {
        setData(password.isEmpty ? nil : Data(password.utf8), .password, for: id)
    }

    static func data(_ item: Item, for id: UUID) -> Data? {
        var query = baseQuery(item, for: id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func setData(_ data: Data?, _ item: Item, for id: UUID) {
        guard let data, !data.isEmpty else {
            SecItemDelete(baseQuery(item, for: id) as CFDictionary)
            return
        }
        let status = SecItemUpdate(baseQuery(item, for: id) as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var newItem = baseQuery(item, for: id)
            newItem[kSecValueData as String] = data
            SecItemAdd(newItem as CFDictionary, nil)
        }
    }

    static func deleteAll(for id: UUID) {
        setData(nil, .password, for: id)
        setData(nil, .clientKey, for: id)
    }

    private static func baseQuery(_ item: Item, for id: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString + item.rawValue,
        ]
    }
}
