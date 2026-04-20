#!/bin/bash

# ─────────────────────────────────────────────────────────────────────────────
# this_cert_check.sh
#
# Scans the certificates/ folder in the repo (NOT the repo root) for new
# .crt / .cer files whose alias does NOT yet exist in the truststore.
#
# Workflow:
#   1. prady commits .crt file into certificates/ folder in GitHub repo
#   2. Jenkins checks out repo → certificates/ appears in workspace
#   3. This script scans certificates/ for new aliases not in truststore
#   4. Pipeline proceeds if new cert found, skips if all already imported
#   5. After deployment, certs are git mv'd to certificates/deployed/
#      and pushed back to GitHub so next checkout does not re-trigger
#
# Usage  : this_cert_check.sh <truststore_path> <truststore_password>
# Scans  : ./certificates/   (relative to Jenkins workspace)
# Skips  : ./certificates/deployed/  (already processed)
# Returns: 0 = at least one NEW cert found  → pipeline proceeds
#          1 = all already imported OR none found → pipeline skips
# ─────────────────────────────────────────────────────────────────────────────

TRUSTSTORE="$1"
TRUSTSTORE_PASS="$2"

# Always scan the certificates/ subfolder — never the repo root
CERT_DIR="./certificates"

if [ -z "$TRUSTSTORE" ] || [ -z "$TRUSTSTORE_PASS" ]; then
    echo "Usage: $0 <truststore_path> <truststore_password>"
    exit 1
fi

if [ ! -d "$CERT_DIR" ]; then
    echo "certificates/ folder not found in workspace. No certs to process."
    exit 1
fi

echo "Scanning for certificate files in: $CERT_DIR"
echo "(Skipping deployed/ subfolder — those are already processed)"
echo ""

# Find certs in certificates/ but NOT in certificates/deployed/
CERT_FILES=$(find "$CERT_DIR" -maxdepth 1 -type f \( -name "*.crt" -o -name "*.cer" \))

if [ -z "$CERT_FILES" ]; then
    echo "No certificate files found in certificates/ folder."
    echo "To deploy a cert: commit your .crt file to the certificates/ folder in GitHub."
    exit 1
fi

echo "Found certificate file(s) in certificates/:"
echo "$CERT_FILES"
echo ""

# If truststore does not exist yet — all certs are new
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

