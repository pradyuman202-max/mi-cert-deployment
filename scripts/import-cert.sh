#!/bin/bash

CERT_FILE=$1
TRUSTSTORE=$2
PASSWORD=$3
ALIAS=$4

echo "Starting certificate import for alias: $ALIAS"

# Create backup if truststore exists
if [ -f "$TRUSTSTORE" ]; then
    BACKUP_DIR="truststore-backups"
    mkdir -p "$BACKUP_DIR"

    BACKUP_FILE="$BACKUP_DIR/$(basename "$TRUSTSTORE")_$(date +%Y%m%d_%H%M%S).jks"
    cp "$TRUSTSTORE" "$BACKUP_FILE"

    echo "Backup created: $BACKUP_FILE"
else
    echo "Truststore not found. No backup taken."
fi

# Import certificate (force overwrite behavior)
keytool -delete -alias "$ALIAS" -keystore "$TRUSTSTORE" -storepass "$PASSWORD" > /dev/null 2>&1

keytool -importcert \
    -trustcacerts \
    -alias "$ALIAS" \
    -file "$CERT_FILE" \
    -keystore "$TRUSTSTORE" \
    -storepass "$PASSWORD" \
    -noprompt

echo "Certificate imported successfully for alias: $ALIAS"

echo "Current truststore entries for alias:"
keytool -list -keystore "$TRUSTSTORE" -storepass "$PASSWORD" | grep -i "$ALIAS"

exit 0
