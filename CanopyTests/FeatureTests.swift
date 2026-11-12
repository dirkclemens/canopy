import Foundation
import Testing
@testable import Canopy

@Suite("Diff")
struct TextDiffTests {
    @Test func identicalTexts() {
        let lines = TextDiff.diff(old: "a\nb", new: "a\nb")
        #expect(lines.allSatisfy { $0.kind == .unchanged })
        #expect(lines.count == 2)
    }

    @Test func changedLine() {
        let lines = TextDiff.diff(old: "a\nb\nc", new: "a\nB\nc\nd")
        #expect(lines.map(\.kind) == [.unchanged, .added, .removed, .unchanged, .added]
             || lines.map(\.kind) == [.unchanged, .removed, .added, .unchanged, .added])
        #expect(lines.filter { $0.kind == .added }.map(\.text) == ["B", "d"])
        #expect(lines.filter { $0.kind == .removed }.map(\.text) == ["b"])
        #expect(lines.last?.newNumber == 4)
    }
}

@Suite("Diagramm-Werte")
struct NumericSeriesTests {
    private func message(_ payload: String, _ offset: TimeInterval = 0) -> ReceivedMessage {
        ReceivedMessage(topic: "t", payload: Data(payload.utf8), qos: .atMostOnce, retained: false,
                        receivedAt: Date(timeIntervalSince1970: 1000 + offset))
    }

    @Test func plainNumbers() {
        #expect(NumericSeries.values(of: message("21.5")) == [NumericSeries.valueKey: 21.5])
        #expect(NumericSeries.values(of: message("ON")) == [NumericSeries.valueKey: 1])
        #expect(NumericSeries.values(of: message("hallo")).isEmpty)
    }

    @Test func jsonLeaves() {
        let values = NumericSeries.values(of: message(#"{"temp": 20, "sensor": {"hum": "55.5", "ok": true}, "arr": [1, "x"]}"#))
        #expect(values == ["temp": 20, "sensor.hum": 55.5, "sensor.ok": 1, "arr[0]": 1])
    }

    @Test func pointsAreSortedByDate() {
        let messages = [message("3", 3), message("1", 1), message("x", 2)]
        #expect(NumericSeries.points(for: NumericSeries.valueKey, in: messages).map(\.value) == [1, 3])
        #expect(NumericSeries.keys(in: messages) == [NumericSeries.valueKey])
    }
}

@Suite("Export")
struct ExportTests {
    private let messages = [
        ReceivedMessage(topic: "a/b", payload: Data("x,\"y\"".utf8), qos: .atLeastOnce, retained: true,
                        receivedAt: Date(timeIntervalSince1970: 0)),
        ReceivedMessage(topic: "bin", payload: Data([0xff]), qos: .atMostOnce, retained: false,
                        receivedAt: Date(timeIntervalSince1970: 1),
                        properties: MessageProperties(contentType: "app/x",
                                                      userProperties: [UserProperty(key: "k", value: "v")])),
    ]

    @Test func csv() {
        let lines = MessageExporter.csv(messages).components(separatedBy: "\r\n")
        #expect(lines[0] == "timestamp,topic,qos,retained,payload")
        #expect(lines[1] == "1970-01-01T00:00:00.000Z,a/b,1,true,\"x,\"\"y\"\"\"")
        #expect(lines[2].hasSuffix(",bin,0,false,base64:/w=="))
    }

    @Test func json() throws {
        let data = MessageExporter.json(messages)
        let array = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(array.count == 2)
        #expect(array[0]["payload"] as? String == "x,\"y\"")
        #expect(array[1]["payloadBase64"] as? String == "/w==")
        let properties = try #require(array[1]["properties"] as? [String: Any])
        #expect(properties["contentType"] as? String == "app/x")
    }
}

@Suite("Verbindungsprofil")
struct ConnectionProfileTests {
    @Test func secretsAreNotEncoded() throws {
        var profile = ConnectionProfile()
        profile.password = "geheim"
        profile.clientKey = Data("-----BEGIN PRIVATE KEY-----".utf8)
        let json = try #require(String(data: JSONEncoder().encode(profile), encoding: .utf8))
        #expect(!json.contains("geheim"))
        #expect(!json.contains("PRIVATE KEY"))
    }

    @Test func decodesOlderFilesWithDefaults() throws {
        let json = #"{"id":"8C3B5E8A-4D2E-4F8B-9A39-3B1C3B3B3B3B","name":"Alt","transport":"mqtts","host":"h","port":8883,"#
            + #""basePath":"/mqtt","username":"","clientID":"c","keepAlive":30,"cleanSession":true,"#
            + #""validateCertificate":false,"subscriptions":[]}"#
        let profile = try JSONDecoder().decode(ConnectionProfile.self, from: Data(json.utf8))
        #expect(profile.name == "Alt")
        #expect(profile.protocolVersion == .v311)
        #expect(profile.transport == .mqtts)
        #expect(profile.keepAlive == 30)
        #expect(profile.validateCertificate == false)
        #expect(profile.caCertificate == nil)
    }

    @Test func roundTrip() throws {
        var profile = ConnectionProfile()
        profile.protocolVersion = .v5
        profile.caCertificate = ImportedFile(fileName: "ca.pem", data: Data([1, 2, 3]))
        let decoded = try JSONDecoder().decode(ConnectionProfile.self, from: JSONEncoder().encode(profile))
        #expect(decoded == profile)
    }

    @Test func mTLSNeedsCertificateAndKey() {
        var profile = ConnectionProfile()
        profile.transport = .mqtts
        profile.clientKey = Data("key".utf8)
        #expect(profile.validationError != nil)
        profile.clientCertificate = ImportedFile(fileName: "c.pem", data: Data())
        #expect(profile.validationError == nil)
    }

    @Test func displayURL() {
        var profile = ConnectionProfile()
        profile.transport = .wss
        profile.host = "broker"
        profile.port = 443
        profile.basePath = "mqtt"
        #expect(profile.displayURL == "wss://broker:443/mqtt")
    }

    @Test func invalidCertificateDataIsRejected() {
        #expect(CertificateLoader.certificates(from: Data("kein zertifikat".utf8)).isEmpty)
        #expect(throws: CertificateError.self) {
            try CertificateLoader.caCertificates(for: ImportedFile(fileName: "x.pem", data: Data("x".utf8)))
        }
    }
}

@Suite("Sitzungsspeicher", .serialized)
struct SessionStorageCleanerTests {
    private func storageExists(_ clientID: String) -> Bool {
        let name = "cocomqtt-" + clientID
        return !(UserDefaults(suiteName: name)?.persistentDomain(forName: name)?.isEmpty ?? true)
    }

    private func createStorage(_ clientID: String) {
        let defaults = UserDefaults(suiteName: "cocomqtt-" + clientID)
        defaults?.set("x", forKey: "test")
        defaults?.synchronize()
    }

    @Test func removesStorageOfClient() {
        let id = "canopy-test-" + UUID().uuidString.prefix(8)
        createStorage(id)
        #expect(storageExists(id))
        SessionStorageCleaner.removeStorage(forClientID: id)
        #expect(!storageExists(id))
    }

    @Test func keepsPersistentSessions() {
        let keepID = "canopy-keep-" + UUID().uuidString.prefix(8)
        let dropID = "canopy-drop-" + UUID().uuidString.prefix(8)
        createStorage(keepID)
        createStorage(dropID)
        var persistent = ConnectionProfile()
        persistent.clientID = keepID
        persistent.cleanSession = false
        SessionStorageCleaner.removeUnusedStorage(keeping: [persistent])
        #expect(storageExists(keepID))
        #expect(!storageExists(dropID))
        SessionStorageCleaner.removeStorage(forClientID: keepID)
    }
}
