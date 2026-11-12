Test-Zertifikate (nur für Tests, selbstsigniert). Erneuern mit `./make-certs.sh`.
macOS akzeptiert Server-Zertifikate nur mit max. 398 Tagen Laufzeit, daher laufen sie nach 397 Tagen ab.

- `test-ca.pem` – Test-CA (der private CA-Schlüssel wird nach dem Erzeugen verworfen)
- `test-server.pem` / `test-server.key` – Server für 127.0.0.1
- `test-client.pem` / `test-client.key` – Client-Zertifikat für mTLS

Broker für die Integrationstests (aus dem Projektverzeichnis):

    mosquitto -c mqttxTests/Fixtures/mosquitto-test.conf
