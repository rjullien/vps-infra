#!/bin/bash
# Migration script: Docker -> Kubernetes (k3s)

set -e

VW_DATA_PATH="/root/vaultwarden/vw-data"
PVC_NAME="vaultwarden-data"
NAMESPACE="default"

echo "=== Vaultwarden Migration: Docker -> k3s ==="

# Check if Docker container is running
if docker ps | grep -q vaultwarden; then
    echo "[1/4] Stopping Docker vaultwarden..."
    docker stop vaultwarden
fi

# Check if PVC already exists
if kubectl get pvc ${PVC_NAME} -n ${NAMESPACE} 2>/dev/null; then
    echo "[2/4] PVC already exists, skipping creation"
else
    echo "[2/4] Creating PVC..."
    kubectl apply -f workloads/vaultwarden/vaultwarden.yaml -n ${NAMESPACE}
fi

# Wait for PVC to be bound
echo "[3/4] Waiting for PVC to be bound..."
kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/${PVC_NAME} -n ${NAMESPACE} --timeout=60s

# Find the PVC path on the node
echo "[4/4] Copying data to PVC..."
PVC_PATH=$(kubectl get pv -o jsonpath='{.items[0].spec.local.path}' -l pvcName=${PVC_NAME})

if [ -z "$PVC_PATH" ]; then
    echo "Error: Could not find PVC path"
    echo "Manual copy required. Data location: /var/lib/rancher/k3s/storage/"
    exit 1
fi

# Copy data
echo "Copying from ${VW_DATA_PATH} to ${PVC_PATH}"
sudo cp -r ${VW_DATA_PATH}/* ${PVC_PATH}/

echo "=== Migration complete ==="
echo "You can now deploy vaultwarden on k3s"
