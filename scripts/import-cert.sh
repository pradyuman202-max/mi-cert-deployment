#!/bin/bash

CERT_FILE=$1
TRUSTSTORE=$2
PASSWORD=$3
ALIAS=$4

BACKUP_DIR="truststore-backups"

mkdir -p $BACKUP_DIR

echo "Creating truststore backup..."
BACKUP_FILE="$BACKUP_DIR/$(basename $TRUSTSTORE)_$(date +%Y%m%d_%H%M%S).jks"
cp $TRUSTSTORE $BACKUP_FILE
echo "Backup created: $BACKUP_FILE"

echo "Checking if certificate already exists..."

if keytool -list -keystore $TRUSTSTORE -storepass $PASSWORD -alias $ALIAS > /dev/null 2>&1
then
    echo "Certificate alias already exists. Skipping import."
else
    echo "Importing certificate..."

    keytool -importcert \
        -trustcacerts \
        -alias $ALIAS \
        -file $CERT_FILE \
        -keystore $TRUSTSTORE \
        -storepass $PASSWORD \
        -noprompt

    echo "Certificate imported successfully"
fi

echo "Current truststore entries:"
keytool -list -keystore $TRUSTSTORE -storepass $PASSWORD
