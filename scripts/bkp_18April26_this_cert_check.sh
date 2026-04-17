#!/bin/bash

CERT_DIR="/home/svc_account_wso2/SIT_MI_Docker_Project"

echo "Checking for certificate files in $CERT_DIR..."

CERT_FOUND=$(find "$CERT_DIR" -maxdepth 1 -type f \( -name "*.crt" -o -name "*.cer" \) | head -n 1)

if [ -n "$CERT_FOUND" ]; then
    echo "Certificate file detected: $CERT_FOUND"
    exit 0
else
    echo "No certificate files found."
    exit 1
fi
