#!/bin/bash

# ─────────────────────────────────────────────────────────
# this_cert_check.sh
# Checks for new certificate files in the CURRENT directory
# (Jenkins workspace after checkout — not a hardcoded server path)
# Returns: 0 if cert found, 1 if none
# ─────────────────────────────────────────────────────────

CERT_DIR="${1:-.}"   # Default to current dir; pass path as arg if needed

echo "Checking for certificate files in: $(realpath $CERT_DIR)"

CERT_FILES=$(find "$CERT_DIR" -maxdepth 1 -type f \( -name "*.crt" -o -name "*.cer" \))
CERT_COUNT=$(echo "$CERT_FILES" | grep -c . || true)

if [ -n "$CERT_FILES" ]; then
    echo "Certificate file(s) detected (${CERT_COUNT} total):"
    echo "$CERT_FILES"
    exit 0
else
    echo "No certificate files found."
    exit 1
fi
