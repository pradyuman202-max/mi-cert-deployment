#!/bin/bash

# ─────────────────────────────────────────────────────────────────────────────
# this_cert_check.sh
#
# TWO-TIER check — fast first, keytool only when needed:
#
#   TIER 1 (fast — file check):
#     If cert filename already exists in SERVER_DEPLOYED_DIR
#     → cert was previously deployed and moved there
#     → skip instantly, no keytool needed
#
#   TIER 2 (slow — keytool check):
#     Only for certs NOT found in SERVER_DEPLOYED_DIR
#     → check alias against truststore via keytool
#     → NEW alias  → pipeline proceeds
#     → OLD alias  → skip
#
# This saves a JVM startup + keystore parse for every already-deployed cert.
# With 29 certs, tier 1 handles 28 in milliseconds, tier 2 runs once for new.
#
# Usage  : this_cert_check.sh <truststore_path> <truststore_password>
# Scans  : ./certificates/          (Jenkins workspace — from git checkout)
# Skips  : ./certificates/deployed/ (already processed in git)
# Also skips if found in: SERVER_DEPLOYED_DIR (see below)
# Returns: 0 = at least one NEW cert found  → pipeline proceeds
#          1 = all already deployed OR none found → pipeline skips
# ─────────────────────────────────────────────────────────────────────────────

TRUSTSTORE="$1"
TRUSTSTORE_PASS="$2"

# Server-side deployed folder — certs physically moved here after deployment
# Acts as a fast lookup cache — no keytool needed for certs found here
SERVER_DEPLOYED_DIR="/home/svc_account_wso2/SIT_MI_Docker_Project/certificates/deployed"

# Workspace scan folder — where new certs are committed in GitHub
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
echo "(Skipping deployed/ subfolder — those are already processed in git)"
echo ""

# Find certs in certificates/ root only — not in deployed/ subfolder
CERT_FILES=$(find "$CERT_DIR" -maxdepth 1 -type f \( -name "*.crt" -o -name "*.cer" \))

if [ -z "$CERT_FILES" ]; then
    echo "No certificate files found in certificates/ folder."
    echo "To deploy a cert: commit your .crt file into certificates/ in GitHub."
    exit 1
fi

echo "Found certificate file(s) in certificates/:"
echo "$CERT_FILES"
echo ""

NEW_CERT_FOUND=0
TIER1_SKIPPED=0
TIER2_CHECKED=0

echo "════════════════════════════════════════════════════════"
echo "TIER 1 — Fast check: server deployed folder"
echo "  Path: $SERVER_DEPLOYED_DIR"
echo "════════════════════════════════════════════════════════"

# Collect certs that pass Tier 1 (not in server deployed folder)
TIER2_CERTS=""

while IFS= read -r CERT; do
    FILENAME=$(basename "$CERT")

    if [ -f "${SERVER_DEPLOYED_DIR}/${FILENAME}" ]; then
        echo "SKIP (T1): $FILENAME — already in server deployed folder"
        TIER1_SKIPPED=$((TIER1_SKIPPED + 1))
    else
        echo "UNKNOWN  : $FILENAME — not in server deployed folder, needs keytool check"
        TIER2_CERTS="$TIER2_CERTS $CERT"
    fi
done <<< "$CERT_FILES"

echo ""
echo "Tier 1 result: $TIER1_SKIPPED cert(s) skipped via fast file check"
echo ""

# If all certs were handled by Tier 1, skip entirely
if [ -z "$(echo $TIER2_CERTS | tr -d ' ')" ]; then
    echo "All certificates already deployed (Tier 1). Pipeline will skip."
    exit 1
fi

echo "════════════════════════════════════════════════════════"
echo "TIER 2 — Keytool check: alias against truststore"
echo "  Only for certs not found in server deployed folder"
echo "════════════════════════════════════════════════════════"

# If truststore doesn't exist yet — all remaining certs are new
if [ ! -f "$TRUSTSTORE" ]; then
    echo "Truststore not found — treating all remaining certs as new."
    exit 0
fi

for CERT in $TIER2_CERTS; do
    ALIAS=$(basename "$CERT" | cut -d. -f1)
    TIER2_CHECKED=$((TIER2_CHECKED + 1))

    EXISTS=$(keytool -list \
        -keystore "$TRUSTSTORE" \
        -storepass "$TRUSTSTORE_PASS" \
        2>/dev/null | grep -ic "^${ALIAS},")

    if [ "$EXISTS" -eq 0 ]; then
        echo "NEW      : $CERT  (alias: $ALIAS — not in truststore)"
        NEW_CERT_FOUND=1
    else
        echo "EXISTING : $CERT  (alias: $ALIAS — in truststore but not in deployed folder)"
        echo "           → Will add to deployed folder to speed up future runs"
        NEW_CERT_FOUND=0
    fi
done

echo ""
echo "════════════════════════════════════════════════════════"
echo "Summary: Tier 1 skipped=$TIER1_SKIPPED  Tier 2 checked=$TIER2_CHECKED"

if [ "$NEW_CERT_FOUND" -eq 1 ]; then
    echo "Result: NEW certificate(s) detected — pipeline will proceed."
    exit 0
else
    echo "Result: All certificate(s) already deployed — pipeline will skip."
    exit 1
fi

