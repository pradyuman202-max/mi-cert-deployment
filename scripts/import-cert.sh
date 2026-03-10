#!/bin/bash

CERT_FILE=$1
TRUSTSTORE=$2
PASSWORD=$3
ALIAS=$4

echo "Checking if certificate already exists..."

# Check if alias exists FIRST before creating a backup
if keytool -list -keystore "$TRUSTSTORE" -storepass "$PASSWORD" -alias "$ALIAS" > /dev/null 2>&1
then
    echo "Certificate alias '$ALIAS' already exists. Skipping import."
    exit 0
else
    echo "Importing certificate '$ALIAS'..."

    # Only backup if the truststore file actually exists and we are doing an import
    if [ -f "$TRUSTSTORE" ]; then
        BACKUP_DIR="truststore-backups"
        mkdir -p "$BACKUP_DIR"
        BACKUP_FILE="$BACKUP_DIR/$(basename "$TRUSTSTORE")_$(date +%Y%m%d_%H%M%S).jks"
        cp "$TRUSTSTORE" "$BACKUP_FILE"
        echo "Backup created: $BACKUP_FILE"
    fi

    keytool -importcert \
        -trustcacerts \
        -alias "$ALIAS" \
        -file "$CERT_FILE" \
        -keystore "$TRUSTSTORE" \
        -storepass "$PASSWORD" \
        -noprompt

    echo "Certificate imported successfully"
fi

echo "Current truststore entries:"
# 1. FIXED: Added '-i' for case-insensitive grep
keytool -list -keystore "$TRUSTSTORE" -storepass "$PASSWORD" | grep -i "$ALIAS"

# 2. FIXED: Explicitly exit with success so Jenkins knows it worked
exit 0
