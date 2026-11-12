import Foundation
import Observation

/// Persists saved connection profiles ("Favoriten") as JSON in Application Support.
/// Passwords go to the Keychain.
@Observable
final class ConnectionStore {
    private(set) var profiles: [ConnectionProfile] = []
    var lastError: String?

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let directory = support.appendingPathComponent("Canopy", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            self.fileURL = directory.appendingPathComponent("connections.json")
        }
        load()
        SessionStorageCleaner.removeUnusedStorage(keeping: profiles)
    }

    func profile(with id: UUID?) -> ConnectionProfile? {
        profiles.first { $0.id == id }
    }

    func save(_ profile: ConnectionProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        KeychainHelper.setPassword(profile.password, for: profile.id)
        KeychainHelper.setData(profile.clientKey, .clientKey, for: profile.id)
        persist()
    }

    func delete(_ id: UUID) {
        profiles.removeAll { $0.id == id }
        KeychainHelper.deleteAll(for: id)
        persist()
    }

    func duplicate(_ id: UUID) -> ConnectionProfile? {
        guard var copy = profile(with: id) else { return nil }
        copy.id = UUID()
        copy.name += " (Kopie)"
        copy.clientID = ConnectionProfile.randomClientID()
        save(copy)
        return copy
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            var loaded = try JSONDecoder().decode([ConnectionProfile].self, from: data)
            for index in loaded.indices {
                loaded[index].password = KeychainHelper.password(for: loaded[index].id)
                loaded[index].clientKey = KeychainHelper.data(.clientKey, for: loaded[index].id)
            }
            profiles = loaded
        } catch {
            lastError = "Verbindungen konnten nicht geladen werden: \(error.localizedDescription)"
        }
    }

    private func persist() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(profiles).write(to: fileURL, options: .atomic)
        } catch {
            lastError = "Verbindungen konnten nicht gespeichert werden: \(error.localizedDescription)"
        }
    }
}
