#!/bin/bash

CERT_DIR="/home/svc_account_wso2/SIT_MI"

echo "Checking for certificate files in $CERT_DIR..."

CERT_FOUND=$(find "$CERT_DIR" -type f \( -name "*.crt" -o -name "*.cer" \) | head -n 1)

if [ -n "$CERT_FOUND" ]; then
    echo "Certificate file detected: $CERT_FOUND"
    exit 0
else
    echo "No certificate files found."
    exit 1
fi
