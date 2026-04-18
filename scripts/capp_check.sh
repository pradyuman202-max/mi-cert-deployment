#!/bin/bash

# ─────────────────────────────────────────────────────────────────────────────
# capp_check.sh
#
# Detects whether any .car file in the workspace (HelloWorld/) is:
#   - BRAND NEW   : filename not present in the deployed capps/ directory
#   - UPDATED     : filename exists but checksum has changed (new version)
#
# If nothing changed → exit 1 (pipeline skips all stages)
# If any new or changed .car found → exit 0 (pipeline proceeds)
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

echo "Scanning for .car files in workspace: $WORKSPACE_DIR"
CAR_FILES=$(find "$WORKSPACE_DIR" -name "*.car" -type f)

if [ -z "$CAR_FILES" ]; then
    echo "No .car files found in workspace. Nothing to deploy."
    exit 1
fi

echo "Found .car file(s):"
echo "$CAR_FILES"
echo ""

CHANGE_FOUND=0

echo "Comparing against deployed capps in: $DEPLOYED_DIR"
echo "────────────────────────────────────────────────────────"

while IFS= read -r CAR; do
    FILENAME=$(basename "$CAR")
    DEPLOYED_FILE="${DEPLOYED_DIR}/${FILENAME}"

    if [ ! -f "$DEPLOYED_FILE" ]; then
        echo "NEW     : $FILENAME — not in deployed capps/"
        CHANGE_FOUND=1
    else
        # Compare checksums to detect version change
        WORKSPACE_MD5=$(md5sum "$CAR"          | awk '{print $1}')
        DEPLOYED_MD5=$(md5sum "$DEPLOYED_FILE" | awk '{print $1}')

        if [ "$WORKSPACE_MD5" != "$DEPLOYED_MD5" ]; then
            echo "UPDATED : $FILENAME — checksum changed (new version)"
            echo "          workspace : $WORKSPACE_MD5"
            echo "          deployed  : $DEPLOYED_MD5"
            CHANGE_FOUND=1
        else
            echo "UNCHANGED: $FILENAME — same checksum, already deployed"
        fi
    fi
done <<< "$CAR_FILES"

echo "────────────────────────────────────────────────────────"

if [ "$CHANGE_FOUND" -eq 1 ]; then
    echo "Result: New or updated CApp(s) detected — pipeline will proceed."
    exit 0
else
    echo "Result: All CApp(s) already deployed and unchanged — pipeline will skip."
    exit 1
fi
