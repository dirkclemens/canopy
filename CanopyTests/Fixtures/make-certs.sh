#!/bin/sh
# Regenerates the TLS test fixtures. macOS rejects server certificates that are
# valid for more than 398 days, so the server certificate expires after 397 days;
# re-run this script when the TLS integration tests start failing.
set -e
cd "$(dirname "$0")"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

openssl req -x509 -newkey rsa:2048 -nodes -keyout "$tmp/ca.key" -out test-ca.pem \
    -days 3650 -subj "/CN=Canopy Test CA" 2>/dev/null

openssl req -newkey rsa:2048 -nodes -keyout test-server.key -out "$tmp/server.csr" \
    -subj "/CN=127.0.0.1" 2>/dev/null
printf "subjectAltName=IP:127.0.0.1,DNS:localhost\nextendedKeyUsage=serverAuth\n" > "$tmp/server.ext"
openssl x509 -req -in "$tmp/server.csr" -CA test-ca.pem -CAkey "$tmp/ca.key" -CAcreateserial \
    -CAserial "$tmp/ca.srl" -out test-server.pem -days 397 -extfile "$tmp/server.ext" 2>/dev/null

openssl req -newkey rsa:2048 -nodes -keyout test-client.key -out "$tmp/client.csr" \
    -subj "/CN=canopy-test-client" 2>/dev/null
printf "extendedKeyUsage=clientAuth\n" > "$tmp/client.ext"
openssl x509 -req -in "$tmp/client.csr" -CA test-ca.pem -CAkey "$tmp/ca.key" -CAserial "$tmp/ca.srl" \
    -out test-client.pem -days 397 -extfile "$tmp/client.ext" 2>/dev/null

echo "Test-Zertifikate erneuert (gültig bis $(openssl x509 -enddate -noout -in test-server.pem | cut -d= -f2))."
