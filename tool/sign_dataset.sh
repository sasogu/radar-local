#!/usr/bin/env bash
set -euo pipefail

# Signs the published dataset with the Ed25519 key kept in pass.
# The private key only exists in a 0600 temporary file during signing.
cd "$(dirname "$0")/.."
DATA="${1:-assets/data/spain-radars.json}"
umask 077
KEY="$(mktemp)"
trap 'rm -f "$KEY"' EXIT
pass show radar-local/dataset-signing-key > "$KEY"
openssl pkeyutl -sign -inkey "$KEY" -rawin -in "$DATA" | base64 -w0 > "$DATA.sig"
rm -f "$KEY"
openssl pkeyutl -verify -pubin -inkey tool/dataset-signing-public.pem -rawin \
  -in "$DATA" -sigfile <(base64 -d "$DATA.sig") >/dev/null
echo "Signed $DATA"
