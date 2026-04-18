#!/bin/bash

# ─────────────────────────────────────────────────────────────────────────────
# capp_check.sh
#
# Detects ALL three types of CApp changes:
#   - NEW     : .car in workspace but NOT in deployed capps/
#   - UPDATED : .car in both, but checksum changed (new version)
#   - DELETED : .car in deployed capps/ but NOT in workspace (removed from repo)
#
# Any of the above → exit 0 (pipeline proceeds with full deploy)
# No changes at all → exit 1 (pipeline skips all stages)
#
# Usage  : capp_check.sh <workspace_car_dir> <deployed_capps_dir>
# Example: capp_check.sh HelloWorld /home/svc_account_wso2/SIT_MI_Docker_Project/capps
# ─────────────────────────────────────────────────────────────────────────────

WORKSPACE_DIR="$1"
DEPLOYED_DIR="$2"

if [ -z "$WORKSPACE_DIR" ] || [ -z "$DEPLOYED_DIR" ]; then
    echo "Usage: $0 <workspace_car_dir> <deployed_capps_dir>"
    exit 1
fi

CHANGE_FOUND=0

# ── PASS 1: Check workspace → deployed (NEW and UPDATED) ─────────────────────
echo "=== Pass 1: Checking for NEW or UPDATED CApps ==="
echo "Scanning workspace: $WORKSPACE_DIR"

CAR_FILES=$(find "$WORKSPACE_DIR" -name "*.car" -type f)

if [ -z "$CAR_FILES" ]; then
    echo "No .car files found in workspace."
else
    echo "Found .car file(s) in workspace:"
    echo "$CAR_FILES"
    echo ""
    echo "Comparing against deployed capps in: $DEPLOYED_DIR"
    echo "────────────────────────────────────────────────────────"

    while IFS= read -r CAR; do
        FILENAME=$(basename "$CAR")
        DEPLOYED_FILE="${DEPLOYED_DIR}/${FILENAME}"

        if [ ! -f "$DEPLOYED_FILE" ]; then
            echo "NEW      : $FILENAME — not present in deployed capps/"
            CHANGE_FOUND=1
        else
            WORKSPACE_MD5=$(md5sum "$CAR"          | awk '{print $1}')
            DEPLOYED_MD5=$(md5sum  "$DEPLOYED_FILE" | awk '{print $1}')

            if [ "$WORKSPACE_MD5" != "$DEPLOYED_MD5" ]; then
                echo "UPDATED  : $FILENAME — checksum changed (new version)"
                echo "           workspace : $WORKSPACE_MD5"
                echo "           deployed  : $DEPLOYED_MD5"
                CHANGE_FOUND=1
            else
                echo "UNCHANGED: $FILENAME — same checksum, already deployed"
            fi
        fi
    done <<< "$CAR_FILES"
fi

# ── PASS 2: Check deployed → workspace (DELETED) ─────────────────────────────
echo ""
echo "=== Pass 2: Checking for DELETED CApps ==="
echo "Scanning deployed capps: $DEPLOYED_DIR"

if [ ! -d "$DEPLOYED_DIR" ] || [ -z "$(ls -A "$DEPLOYED_DIR"/*.car 2>/dev/null)" ]; then
    echo "No deployed .car files found in $DEPLOYED_DIR — skipping deletion check."
else
    echo "────────────────────────────────────────────────────────"
    for DEPLOYED_CAR in "$DEPLOYED_DIR"/*.car; do
        FILENAME=$(basename "$DEPLOYED_CAR")

        # Check if this deployed file exists anywhere in workspace dir
        WORKSPACE_MATCH=$(find "$WORKSPACE_DIR" -name "$FILENAME" -type f | head -n 1)

        if [ -z "$WORKSPACE_MATCH" ]; then
            echo "DELETED  : $FILENAME — exists in deployed capps/ but removed from workspace"
            CHANGE_FOUND=1
        else
            echo "PRESENT  : $FILENAME — still in workspace"
        fi
    done
fi

# ── Result ────────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════"

if [ "$CHANGE_FOUND" -eq 1 ]; then
    echo "Result: Change(s) detected — pipeline will proceed with full deployment."
    exit 0
else
    echo "Result: No changes detected — pipeline will skip all stages."
    exit 1
fi
