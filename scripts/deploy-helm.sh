#!/bin/bash
NAMESPACE=${1:-mi}

# Upgrade or install Helm chart
helm upgrade --install mi ../helm -n $NAMESPACE -f ../values.yaml

# Wait for deployment to be ready
kubectl rollout status deployment mi-deployment -n $NAMESPACE

echo "WSO2 MI deployed successfully in namespace $NAMESPACE"
