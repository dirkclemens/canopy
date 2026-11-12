import Foundation

/// CocoaMQTT keeps in-flight QoS 1/2 messages in a UserDefaults suite named
/// `cocomqtt-<clientID>` so a persistent session (Clean Session off) can resume
/// after a restart. For clean sessions this file is useless, and with random
/// client IDs these files pile up — so they are removed here.
enum SessionStorageCleaner {
    private static let prefix = "cocomqtt-"

    /// Removes the session storage of a client that used a clean session.
    static func removeStorage(forClientID clientID: String) {
        let name = prefix + clientID
        // Go through the suite itself: cfprefsd caches the domain, so deleting only
        // the file would be undone. An emptied domain is removed by cfprefsd.
        if let suite = UserDefaults(suiteName: name) {
            for key in (suite.persistentDomain(forName: name) ?? [:]).keys {
                suite.removeObject(forKey: key)
            }
            suite.removePersistentDomain(forName: name)
            suite.synchronize()
        }
        try? FileManager.default.removeItem(at: preferencesDirectory.appendingPathComponent(name + ".plist"))
    }

    /// Removes all session storage except that of saved profiles with Clean Session off.
    static func removeUnusedStorage(keeping profiles: [ConnectionProfile]) {
        let keep = Set(profiles.filter { !$0.cleanSession }.map(\.clientID))
        let files = (try? FileManager.default.contentsOfDirectory(atPath: preferencesDirectory.path)) ?? []
        for file in files where file.hasPrefix(prefix) && file.hasSuffix(".plist") {
            let clientID = String(file.dropFirst(prefix.count).dropLast(".plist".count))
            if !keep.contains(clientID) {
                removeStorage(forClientID: clientID)
            }
        }
    }

    private static var preferencesDirectory: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Preferences", isDirectory: true)
    }
}
