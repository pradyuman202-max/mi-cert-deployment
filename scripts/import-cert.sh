#!/bin/bash

set -e

CERT_FILE=$1
TRUSTSTORE=$2
PASSWORD=$3
ALIAS=$4

BACKUP_DIR=truststore-backups
DATE=$(date +%Y%m%d_%H%M%S)

echo "Creating truststore backup..."

mkdir -p $BACKUP_DIR

if [ -f "$TRUSTSTORE" ]; then
cp $TRUSTSTORE $BACKUP_DIR/client-truststore_$DATE.jks
echo "Backup created: $BACKUP_DIR/client-truststore_$DATE.jks"
else
echo "Truststore not found, will create new one."
fi

echo "Checking if certificate already exists..."

if keytool -list -keystore $TRUSTSTORE -storepass $PASSWORD 2>/dev/null | grep -q $ALIAS; then
echo "Certificate alias already exists. Skipping import."
else
echo "Importing certificate..."

```
keytool -import \
    -alias $ALIAS \
    -file $CERT_FILE \
    -keystore $TRUSTSTORE \
    -storepass $PASSWORD \
    -noprompt

echo "Certificate imported successfully."
```

fi

echo "Current truststore entries:"
keytool -list -keystore $TRUSTSTORE -storepass $PASSWORD


