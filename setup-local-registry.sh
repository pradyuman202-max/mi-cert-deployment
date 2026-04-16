#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# setup-local-registry.sh
# Run this ONCE on your WSL2/Windows machine before the first Jenkins build.
# ─────────────────────────────────────────────────────────────────────────────

set -e

REGISTRY_PORT=5000
REGISTRY_NAME="local-registry"

echo "=== Step 1: Start local Docker registry ==="
if docker ps --format '{{.Names}}' | grep -q "^${REGISTRY_NAME}$"; then
    echo "Registry '${REGISTRY_NAME}' is already running."
else
    docker run -d \
        -p ${REGISTRY_PORT}:5000 \
        --restart=always \
        --name ${REGISTRY_NAME} \
        registry:2
    echo "Registry started at localhost:${REGISTRY_PORT}"
fi

echo ""
echo "=== Step 2: Configure Docker to allow insecure local registry ==="
echo "Add the following to Docker Desktop → Settings → Docker Engine (JSON):"
echo ""
cat <<EOF
{
  "insecure-registries": ["localhost:5000"]
}
EOF

echo ""
echo "=== Step 3: Configure K8s to pull from local registry ==="
echo "If using Docker Desktop K8s, the registry is already accessible."
echo "If using kind, run:"
echo "  kind load docker-image localhost:5000/mi-sit:<tag> --name <cluster-name>"
echo ""
echo "=== Step 4: Verify registry is up ==="
sleep 2
curl -s http://localhost:${REGISTRY_PORT}/v2/_catalog && echo "" && echo "Registry OK!"

echo ""
echo "=== Step 5: Create capps/ directory in Docker project ==="
mkdir -p /home/svc_account_wso2/SIT_MI_Docker_Project/capps
echo "Done. capps/ directory ready."

echo ""
echo "=== Step 6: Ensure mi namespace exists in K8s ==="
kubectl get namespace mi 2>/dev/null || kubectl create namespace mi
echo "Namespace 'mi' is ready."

echo ""
echo "==========================================="
echo "  Setup complete. You can now run Jenkins."
echo "==========================================="

