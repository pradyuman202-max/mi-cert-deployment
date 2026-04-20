#!/bin/bash

# ─────────────────────────────────────────────────────────────────────────────
# this_cert_check.sh
#
# Simple alias check — no tiers, no complexity.
#
# For each .crt / .cer in certificates/ folder:
#   → derive alias from filename
#   → check if alias exists in truststore via keytool
#   → NEW  = not in truststore → pipeline proceeds
#   → OLD  = already in truststore → skip this cert
#
# If ANY new cert found → exit 0 → pipeline deploys
# If ALL certs already imported OR no certs → exit 1 → pipeline skips
#
# After deployment the pipeline moves ALL certs to certificates/deployed/
# on the server. Next run: certificates/ is empty → exit 1 → skip cleanly.
# No need for keytool checks at all on subsequent runs.
#
# Usage  : this_cert_check.sh <truststore_path> <truststore_password>
# Scans  : ./certificates/  (Jenkins workspace, -maxdepth 1 only)
# ─────────────────────────────────────────────────────────────────────────────

TRUSTSTORE="$1"
TRUSTSTORE_PASS="$2"
CERT_DIR="./certificates"

if [ -z "$TRUSTSTORE" ] || [ -z "$TRUSTSTORE_PASS" ]; then
    echo "Usage: $0 <truststore_path> <truststore_password>"
    exit 1
fi

# ── Scan certificates/ folder ────────────────────────────────────────────────
if [ ! -d "$CERT_DIR" ]; then
    echo "certificates/ folder not found in workspace. No certs to process."
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

# ── If truststore missing → all certs are new ────────────────────────────────
if [ ! -f "$TRUSTSTORE" ]; then
    echo "Truststore not found — all certs treated as new."
    exit 0
fi

# ── Check each cert alias against truststore ─────────────────────────────────
echo "Checking aliases against truststore: $TRUSTSTORE"
echo "────────────────────────────────────────────────────────"

NEW_CERT_FOUND=0

while IFS= read -r CERT; do
    ALIAS=$(basename "$CERT" | cut -d. -f1)

    EXISTS=$(keytool -list \
        -keystore "$TRUSTSTORE" \
        -storepass "$TRUSTSTORE_PASS" \
        2>/dev/null | grep -ic "^${ALIAS},")

    if [ "$EXISTS" -eq 0 ]; then
        echo "NEW     : $CERT  (alias: $ALIAS — not in truststore)"
        NEW_CERT_FOUND=1
        # NOTE: do NOT reset to 0 after this — keep scanning for more new certs
        # but result is already decided: pipeline will proceed
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

