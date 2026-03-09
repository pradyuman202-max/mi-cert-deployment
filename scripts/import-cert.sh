#!/bin/bash

CERT_FILE=$1
TRUSTSTORE=$2
PASSWORD=$3
ALIAS=$4

BACKUP_DIR="truststore-backups"
mkdir -p $BACKUP_DIR

echo "Checking if certificate alias '$ALIAS' already exists..."

if keytool -list -keystore $TRUSTSTORE -storepass $PASSWORD -alias $ALIAS > /dev/null 2>&1
then
    echo "Certificate alias '$ALIAS' already exists. Skipping import."
else
    echo "Creating truststore backup..."
    if [ -f "$TRUSTSTORE" ]; then
        BACKUP_FILE="$BACKUP_DIR/$(basename $TRUSTSTORE)_$(date +%Y%m%d_%H%M%S).jks"
        cp $TRUSTSTORE $BACKUP_FILE
        echo "Backup created: $BACKUP_FILE"
    fi

    echo "Importing certificate '$ALIAS'..."

    keytool -importcert \
        -trustcacerts \
        -alias $ALIAS \
        -file $CERT_FILE \
        -keystore $TRUSTSTORE \
        -storepass $PASSWORD \
        -noprompt

    if [ $? -eq 0 ]; then
        echo "Certificate imported successfully"
        # Create a flag file so Jenkins knows a change was actually made
        touch .cert_updated_flag
    else
        echo "Failed to import certificate '$ALIAS'"
        exit 1
    fi
fi
