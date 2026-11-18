#!/usr/bin/env bash
# Generates the synthetic root EKU fixtures in this directory with OpenSSL 3.4 or later.
#
# One root key signs root certificates that differ only in their extensions.
# The same key issues one intermediate, which issues one leaf with the FFE EKU.
# Thus each root variant can anchor the same chain, and a test isolates one root rule.
# All keys are public synthetic test material. Never trust these certificates outside tests.
#
# The FFE EKU OID 1.3.6.1.4.1.99999.1.1 is a placeholder. Datadog must assign the production OID.
set -euo pipefail

OPENSSL="${OPENSSL:-openssl}"
OUT="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FFE_EKU="1.3.6.1.4.1.99999.1.1"
NOT_BEFORE="20261101000000Z"
NOT_AFTER="20361101000000Z"
SUBJECT="/CN=Response Signing Root EKU (test)"

"$OPENSSL" ecparam -name prime256v1 -genkey -noout -out "$WORK/root.key"
"$OPENSSL" ecparam -name prime256v1 -genkey -noout -out "$WORK/intermediate.key"
"$OPENSSL" ecparam -name prime256v1 -genkey -noout -out "$WORK/leaf.key"

# root <name> <pathlen> <extendedKeyUsage or empty>
root() {
    local name="$1" pathlen="$2" usage="$3"
    {
        echo "[ext]"
        echo "basicConstraints = critical, CA:TRUE, pathlen:$pathlen"
        echo "keyUsage = critical, keyCertSign, cRLSign"
        echo "subjectKeyIdentifier = hash"
        echo "authorityKeyIdentifier = none"
        if [ -n "$usage" ]; then
            echo "extendedKeyUsage = $usage"
        fi
    } > "$WORK/$name.cnf"
    "$OPENSSL" req -new -key "$WORK/root.key" -subj "$SUBJECT" -out "$WORK/$name.csr"
    "$OPENSSL" x509 -req -in "$WORK/$name.csr" -key "$WORK/root.key" -sha256 \
        -not_before "$NOT_BEFORE" -not_after "$NOT_AFTER" -set_serial 1 \
        -extfile "$WORK/$name.cnf" -extensions ext -out "$OUT/$name.pem"
}

root root-eku-none 1 ""
root root-eku-ffe 1 "$FFE_EKU"
root root-eku-any 1 "anyExtendedKeyUsage"
root root-eku-codesigning-ffe 1 "codeSigning, $FFE_EKU"
root root-eku-codesigning 1 "codeSigning"
root root-pathlen-0 0 ""

cat > "$WORK/intermediate.cnf" <<EOF
[ext]
basicConstraints = critical, CA:TRUE, pathlen:0
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always
EOF
"$OPENSSL" req -new -key "$WORK/intermediate.key" -subj "/CN=Response Signing Intermediate (test)" \
    -out "$WORK/intermediate.csr"
"$OPENSSL" x509 -req -in "$WORK/intermediate.csr" -CA "$OUT/root-eku-none.pem" -CAkey "$WORK/root.key" \
    -sha256 -not_before "$NOT_BEFORE" -not_after "$NOT_AFTER" -set_serial 2 \
    -extfile "$WORK/intermediate.cnf" -extensions ext -outform DER -out "$WORK/intermediate.der"

cat > "$WORK/leaf.cnf" <<EOF
[ext]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = $FFE_EKU
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always
EOF
"$OPENSSL" x509 -in "$WORK/intermediate.der" -inform DER -out "$WORK/intermediate.pem"
"$OPENSSL" req -new -key "$WORK/leaf.key" -subj "/CN=ffe-signer" -out "$WORK/leaf.csr"
"$OPENSSL" x509 -req -in "$WORK/leaf.csr" -CA "$WORK/intermediate.pem" -CAkey "$WORK/intermediate.key" \
    -sha256 -not_before "$NOT_BEFORE" -not_after "$NOT_AFTER" -set_serial 3 \
    -extfile "$WORK/leaf.cnf" -extensions ext -outform DER -out "$WORK/leaf.der"

"$OPENSSL" pkcs8 -topk8 -nocrypt -in "$WORK/leaf.key" -outform DER -out "$WORK/leaf.pk8"

jq -n \
    --arg k "$(base64 < "$WORK/leaf.pk8" | tr -d '\n')" \
    --arg l "$(base64 < "$WORK/leaf.der" | tr -d '\n')" \
    --arg i "$(base64 < "$WORK/intermediate.der" | tr -d '\n')" \
    '{version: 1, generation: "root-eku-chain", private_key_pkcs8_der_base64: $k,
      certificate_der_base64: $l, intermediates_der_base64: [$i]}' > "$OUT/root-eku-chain.json"
