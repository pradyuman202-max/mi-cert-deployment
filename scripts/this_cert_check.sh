#!/bin/bash

# ─────────────────────────────────────────────────────────────────────────────
# this_cert_check.sh
#
# Checks whether any .crt / .cer in the workspace root is GENUINELY NEW —
# i.e. its derived alias does NOT already exist in the truststore.
#
# This prevents re-triggering the pipeline for certs already imported but
# still sitting in the repo from a previous commit.
#
# Usage  : this_cert_check.sh <truststore_path> <truststore_password>
# Returns: 0 = at least one NEW cert found  → pipeline should proceed
#          1 = all certs already imported OR no certs found → skip
# ─────────────────────────────────────────────────────────────────────────────

TRUSTSTORE="$1"
TRUSTSTORE_PASS="$2"

if [ -z "$TRUSTSTORE" ] || [ -z "$TRUSTSTORE_PASS" ]; then
    echo "Usage: $0 <truststore_path> <truststore_password>"
    exit 1
fi

echo "Scanning workspace root for certificate files..."
CERT_FILES=$(find . -maxdepth 1 -type f \( -name "*.crt" -o -name "*.cer" \))

if [ -z "$CERT_FILES" ]; then
    echo "No certificate files found in workspace root."
    exit 1
fi

echo "Found certificate file(s):"
echo "$CERT_FILES"
echo ""

# If truststore does not exist yet, every cert is new by definition
if [ ! -f "$TRUSTSTORE" ]; then
    echo "Truststore not found — treating all certs as new."
    exit 0
fi

NEW_CERT_FOUND=0

echo "Checking aliases against existing truststore: $TRUSTSTORE"
echo "────────────────────────────────────────────────────────"

while IFS= read -r CERT; do
    ALIAS=$(basename "$CERT" | cut -d. -f1)
    EXISTS=$(keytool -list \
        -keystore "$TRUSTSTORE" \
        -storepass "$TRUSTSTORE_PASS" \
        2>/dev/null | grep -ic "^${ALIAS},")

    if [ "$EXISTS" -eq 0 ]; then
        echo "NEW     : $CERT  (alias: $ALIAS — not in truststore)"
        NEW_CERT_FOUND=1
    else
        echo "EXISTING: $CERT  (alias: $ALIAS — already imported, will skip)"
    fi
done <<< "$CERT_FILES"

echo "────────────────────────────────────────────────────────"

if [ "$NEW_CERT_FOUND" -eq 1 ]; then
    echo "Result: NEW certificate(s) detected — pipeline will proceed."
    exit 0
else
    echo "Result: All certificate(s) already imported — pipeline will skip."
    exit 1
fi
