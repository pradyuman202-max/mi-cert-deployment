#!/bin/bash

# ─────────────────────────────────────────────────────────────────────────────
# this_cert_check.sh
#
# Simple alias check for each .crt / .cer in certificates/ folder.
# For each cert:
#   → derive alias from filename
#   → check if alias exists in truststore
#   → NEW  → pipeline proceeds
#   → OLD  → skip this cert
#
# If ANY new cert found → exit 0 → pipeline deploys
# If ALL already imported OR no certs → exit 1 → pipeline skips
#
# Usage: this_cert_check.sh <truststore_path> <truststore_password>
# ─────────────────────────────────────────────────────────────────────────────

TRUSTSTORE="$1"
TRUSTSTORE_PASS="$2"
CERT_DIR="./certificates"

if [ -z "$TRUSTSTORE" ] || [ -z "$TRUSTSTORE_PASS" ]; then
    echo "Usage: $0 <truststore_path> <truststore_password>"
    exit 1
fi

if [ ! -d "$CERT_DIR" ]; then
    echo "certificates/ folder not found in workspace."
    exit 1
fi

echo "Scanning: $CERT_DIR"
echo ""

CERT_FILES=$(find "$CERT_DIR" -maxdepth 1 -type f \( -name "*.crt" -o -name "*.cer" \))

if [ -z "$CERT_FILES" ]; then
    echo "No certificate files found in certificates/ — nothing to deploy."
    exit 1
fi

echo "Found certificate(s):"
echo "$CERT_FILES"
echo ""

if [ ! -f "$TRUSTSTORE" ]; then
    echo "Truststore not found — all certs treated as new."
    exit 0
fi

echo "Checking aliases against truststore: $TRUSTSTORE"
echo "────────────────────────────────────────────────────────"

NEW_CERT_FOUND=0

while IFS= read -r CERT; do
    ALIAS=$(basename "$CERT" | cut -d. -f1)

    # ── FIX: grep -ic returns exit code 1 when count=0 ──────────────────────
    # Without || echo "0", the subshell exits with code 1 when a new cert is
    # found, crashing the entire loop before NEW_CERT_FOUND can be checked.
    EXISTS=$(keytool -list \
        -keystore "$TRUSTSTORE" \
        -storepass "$TRUSTSTORE_PASS" \
        2>/dev/null | grep -ic "^${ALIAS}," || echo "0")

    if [ "$EXISTS" -eq 0 ]; then
        echo "NEW     : $CERT  (alias: $ALIAS — not in truststore)"
        NEW_CERT_FOUND=1
    else
        echo "EXISTING: $CERT  (alias: $ALIAS — already imported)"
    fi
done <<< "$CERT_FILES"

echo "────────────────────────────────────────────────────────"

if [ "$NEW_CERT_FOUND" -eq 1 ]; then
    echo "Result: NEW certificate(s) detected — pipeline will proceed."
    exit 0
else
    echo "Result: All certificates already imported — pipeline will skip."
    exit 1
fi

