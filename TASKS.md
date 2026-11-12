# mqttX – Ablaufplan

Native macOS-MQTT-Client in Swift/SwiftUI.
Schwerpunkt der ersten Ausbaustufe: die Grundfunktionen.

Status: `[x]` erledigt · `[ ]` offen

---

## Phase 0 – Projekt & Infrastruktur
- [x] Xcode-Projekt `mqttx.xcodeproj` (synchronisierter Ordner `mqttx/`, neue Dateien werden automatisch kompiliert)
- [x] Git-Repository, `.gitignore` (xcuserdata, DerivedData, .DS_Store)
- [x] MQTT-Bibliothek per Swift Package Manager: [CocoaMQTT](https://github.com/emqx/CocoaMQTT) 2.4.x (TCP, TLS, WebSocket)
- [x] App Sandbox: ausgehende Netzwerkverbindungen erlaubt
- [x] Zielplattform auf macOS beschränkt
- [x] Veraltete `mqttx/Info.plist` entfernt (Info.plist wird generiert)

## Phase 1 – Datenmodell
- [x] `ConnectionProfile`: Name, Protokoll (`mqtt://`, `mqtts://`, `ws://`, `wss://`), Host, Port, Basispfad (WebSocket), Benutzername, Passwort, Client-ID, Keep-Alive, Clean Session, TLS-Optionen (Zertifikatsprüfung), Topic-Abonnements inkl. QoS
- [x] `ReceivedMessage`: Topic, Payload (Bytes), QoS, Retained, Zeitstempel
- [x] `TopicNode`: Baumknoten (Segment, Kinder, letzte Nachricht, Historie, Zähler)
- [x] `PayloadFormat`: Erkennung (JSON, XML, Text, Binär) und Darstellungen

## Phase 2 – Persistenz (Einstellungen/Favoriten)
- [x] `ConnectionStore`: Profile als JSON in *Application Support* speichern/laden
- [x] Passwörter im macOS-Schlüsselbund (Keychain) statt im Klartext
- [x] Anlegen, Bearbeiten, Duplizieren, Löschen von Verbindungen

## Phase 3 – MQTT-Service
- [x] `MQTTClientService`: Verbinden/Trennen, Status (getrennt/verbindet/verbunden/Fehler)
- [x] TCP und TLS (`mqtt`/`mqtts`), WebSocket (`ws`/`wss`)
- [x] Option „unsichere Zertifikate akzeptieren“ (selbstsignierte Broker)
- [x] Abonnieren der konfigurierten Topics nach dem Verbindungsaufbau
- [x] Empfangene Nachrichten in den Topic-Baum einsortieren
- [x] Nachrichten veröffentlichen (Topic, Payload, QoS, Retain)

## Phase 4 – Oberfläche
- [x] Startansicht: Liste gespeicherter Verbindungen + Formular zum Konfigurieren
- [x] Verbindungsansicht mit geteiltem Layout (links Baum, rechts Details)
- [x] Topic-Baum (aufklappbar), mit Nachrichtenzähler, Vorschau des Werts, Anzahl Untertopics
- [x] Filter/Suche im Topic-Baum
- [x] Detailansicht: Topic, Metadaten (QoS, Retained, Zeit, Größe), Payload
- [x] Payload-Darstellung: Automatisch, Raw/Text, JSON (formatiert), XML (formatiert), Hex-Dump, Base64, Binär, Dezimal-Bytes
- [x] Kopieren von Topic und Payload in die Zwischenablage
- [x] Nachrichtenhistorie je Topic
- [x] Publish-Bereich
- [x] Toolbar: Trennen, Suche, Export, Baum leeren
- [x] Statuszeile über dem Topic-Baum: Status, Topic-/Nachrichtenzähler; bei Fehlern vollständige Meldung mit „Erneut verbinden“
- [x] Fensterposition und -größe werden gespeichert (`NSWindow`-Frame-Autosave)
- [x] Breite des Topic-Baums wird als Verhältnis zum rechten Bereich gespeichert (`RatioSplitView`, Doppelklick auf Trenner = Standard 40 %)
- [x] Höhe Payload ↔ Verlauf per Trennlinie verstellbar und gespeichert (mind. 4 Zeilen Payload, Doppelklick = Standard 65 %)
- [x] Ausgewähltes Topic wird pro Verbindung gespeichert und beim nächsten Verbinden wieder ausgewählt, aufgeklappt und angezeigt
- [x] Detail/Publish-Split in SwiftUI statt `VSplitView` (Detailansicht wurde teils von der Toolbar verdeckt); Trennlinie wird gespeichert

## Phase 5 – Erweiterungen
- [x] MQTT 5 (CocoaMQTT5) wählbar pro Verbindung; Anzeige von Content-Type, Response-Topic, Correlation-Data, Payload-Format, Ablaufzeit und User Properties; Senden mit Properties
- [x] Eigene CA-Zertifikate (PEM-Bundle/DER) und Client-Zertifikate für mTLS (RSA-Schlüssel PEM, im Schlüsselbund gespeichert)
- [x] Diagramme für numerische Werte (Swift Charts), auch für Zahlen in JSON-Payloads (Pfadauswahl)
- [x] Diff zwischen zwei Nachrichten (Verlauf: ⌘-Klick auf zwei Einträge, sonst letzte vs. vorherige)
- [x] Retained-Nachrichten löschen per Kontextmenü (einzeln oder ganzer Teilbaum, mit Bestätigung)
- [x] Mehrere Verbindungen gleichzeitig: jedes Fenster (⌘N) hat eine eigene Verbindung
- [x] Unit-Tests (Swift Testing) für Topic-Baum, Payload-Formatierung, Highlighting, Diff, Diagrammwerte, Export, Profile
- [x] Integrationstests gegen lokalen Mosquitto (MQTT 3.1.1/5, Retained, TLS, mTLS) – siehe `mqttxTests/Fixtures/README.md`
- [x] Export von Nachrichten als JSON oder CSV (ganzer Baum über die Toolbar, Teilbaum über das Kontextmenü)
- [x] Syntax-Highlighting für JSON und XML

## Phase 6 – Ideen (offen)
- [ ] Client-Identität aus PKCS#12 (.p12) bzw. EC-Schlüssel
- [ ] Verschlüsselte private Schlüssel (Passphrase)
- [ ] Verständliche Fehlermeldung bei abgelehnten Server-Zertifikaten (z. B. Laufzeit > 398 Tage)
- [ ] Payload-Dateien senden (Binär) und Payload-Vorlagen
