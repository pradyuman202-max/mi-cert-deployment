#!/bin/bash

CERT_FILE=$1
TRUSTSTORE=$2
PASSWORD=$3
ALIAS=$4

BACKUP_DIR="truststore-backups"

# Validate inputs
if [ -z "$CERT_FILE" ] || [ -z "$TRUSTSTORE" ] || [ -z "$PASSWORD" ] || [ -z "$ALIAS" ]; then
    echo "Usage: $0 <cert-file> <truststore> <password> <alias>"
    exit 1
fi

if [ ! -f "$CERT_FILE" ]; then
    echo "ERROR: Certificate file not found: $CERT_FILE"
    exit 1
fi

if [ ! -f "$TRUSTSTORE" ]; then
    echo "ERROR: Truststore not found: $TRUSTSTORE"
    exit 1
fi

mkdir -p $BACKUP_DIR

echo "Creating truststore backup..."

BACKUP_FILE="$BACKUP_DIR/$(basename $TRUSTSTORE)$(date +%Y%m%d%H%M%S).jks"

cp $TRUSTSTORE $BACKUP_FILE

echo "Backup created: $BACKUP_FILE"

echo "Checking if certificate alias already exists..."

if keytool -list -keystore $TRUSTSTORE -storepass $PASSWORD -alias $ALIAS > /dev/null 2>&1
then
    echo "Certificate alias already exists. No new certificate imported."
    
    echo "Current truststore entries:"
    keytool -list -keystore $TRUSTSTORE -storepass $PASSWORD
    
    exit 2
else
    echo "Importing certificate..."

    keytool -importcert \
        -trustcacerts \
        -alias $ALIAS \
        -file $CERT_FILE \
        -keystore $TRUSTSTORE \
        -storepass $PASSWORD \
        -noprompt

    if [ $? -ne 0 ]; then
        echo "ERROR: Certificate import failed"
        exit 1
    fi

    echo "Certificate imported successfully"

    echo "Current truststore entries:"
    keytool -list -keystore $TRUSTSTORE -storepass $PASSWORD

    exit 0
fi
