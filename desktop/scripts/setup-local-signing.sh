#!/bin/bash
set -euo pipefail
umask 077
DESKTOP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIGNING_DIR="$HOME/Library/Application Support/Howdoey/DevelopmentSigning"
mkdir -p "$SIGNING_DIR"
chmod 700 "$SIGNING_DIR"
if [ -f "$SIGNING_DIR/identity" ]; then
    swift "$DESKTOP_ROOT/scripts/local-signing-keychain.swift" unlock "$SIGNING_DIR" 2> "$SIGNING_DIR/helper.log"
    printf 'Existing local development identity is ready. No trust settings changed.\n'
    exit 0
fi
if [ ! -f "$SIGNING_DIR/keychain-password" ]; then
    /usr/bin/openssl rand -hex 32 > "$SIGNING_DIR/keychain-password"
    # Store bytes without a trailing newline so keychain creation and PKCS#12 agree.
    python3 - "$SIGNING_DIR/keychain-password" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
p.write_bytes(p.read_bytes().strip())
PY
fi
STAGE_DIR="$(mktemp -d "$SIGNING_DIR/import.XXXXXX")"
trap 'rm -rf "$STAGE_DIR"' EXIT
cat > "$STAGE_DIR/certificate.conf" <<'CONF'
[req]
distinguished_name=subject
x509_extensions=extensions
prompt=no
[subject]
CN=Howdoey Local Development
O=Howdoey Local Development Only
[extensions]
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
subjectKeyIdentifier=hash
CONF
/usr/bin/openssl req -new -newkey rsa:3072 -nodes -x509 -sha256 -days 1825 -config "$STAGE_DIR/certificate.conf" -keyout "$STAGE_DIR/key.pem" -out "$STAGE_DIR/certificate.pem" 2>/dev/null
/usr/bin/openssl pkcs12 -export -name 'Howdoey Local Development' -inkey "$STAGE_DIR/key.pem" -in "$STAGE_DIR/certificate.pem" -passout "file:$SIGNING_DIR/keychain-password" -out "$STAGE_DIR/identity.p12"
swift "$DESKTOP_ROOT/scripts/local-signing-keychain.swift" import "$SIGNING_DIR" "$STAGE_DIR/identity.p12" 2> "$SIGNING_DIR/helper.log"
/usr/bin/openssl x509 -in "$STAGE_DIR/certificate.pem" -noout -fingerprint -sha1 | sed 's/.*=//;s/://g' > "$SIGNING_DIR/identity"
chmod 600 "$SIGNING_DIR/identity" "$SIGNING_DIR/keychain-password" "$SIGNING_DIR/keychain-path"
printf 'Local development signing identity created in a dedicated private keychain.\nNo system or browser trust roots were added. This identity is not for public distribution.\n'
