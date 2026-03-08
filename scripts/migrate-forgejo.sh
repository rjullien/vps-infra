#!/bin/bash
# Migration script: Docker -> Kubernetes (k3s)

set -e

FORGEJO_DATA_PATH="./data"
NAMESPACE="default"

echo "=== Forgejo Migration: Docker -> k3s ==="

# Check if Docker container is running
if docker ps | grep -q forgejo; then
    echo "[1/4] Stopping Docker forgejo..."
    docker stop forgejo
    docker rm forgejo
fi

# Create PVC
echo "[2/4] Creating PVC..."
kubectl apply -f workloads/forgejo/forgejo.yaml -n ${NAMESPACE}

# Wait for PVC to be bound
echo "[3/4] Waiting for PVC to be bound..."
kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/forgejo-data -n ${NAMESPACE} --timeout=60s

# Copy data
echo "[4/4] Copying data to PVC..."
DATA_PV=$(kubectl get pv -l pvcName=forgejo-data -o jsonpath='{.items[0].spec.local.path}')

if [ -z "$DATA_PV" ]; then
    echo "Error: Could not find PVC path"
    exit 1
fi

echo "Copying from ${FORGEJO_DATA_PATH} to ${DATA_PV}"
sudo cp -r ${FORGEJO_DATA_PATH}/* ${DATA_PV}/

# Set permissions
sudo chown -R 1000:1000 ${DATA_PV}/

echo "=== Migration complete ==="
echo ""
echo "Note: SSH is exposed on port 22 inside the container."
echo "To access SSH, use: ssh -p 22 git@git.bapttf.com"
echo "(Make sure port 22 is forwarded to the Forgejo pod)"
echo ""
echo "Deploy to k3s with: kubectl apply -f workloads/forgejo/forgejo.yaml"
