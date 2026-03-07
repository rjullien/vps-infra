#!/bin/bash
# Migration script: Docker -> Kubernetes (k3s)

set -e

COUCHDB_DATA_PATH="./couchdb-data"
COUCHDB_ETC_PATH="./couchdb-etc"
NAMESPACE="default"

echo "=== CouchDB (Obsidian LiveSync) Migration: Docker -> k3s ==="

# Check if Docker container is running
if docker ps | grep -q obsidian-livesync; then
    echo "[1/5] Stopping Docker obsidian-livesync..."
    docker stop obsidian-livesync
fi

# Create PVCs
echo "[2/5] Creating PVCs..."
kubectl apply -f workloads/obsidian-livesync/couchdb.yaml

# Wait for PVCs to be bound
echo "[3/5] Waiting for PVCs to be bound..."
kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/couchdb-data -n ${NAMESPACE} --timeout=60s
kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/couchdb-etc -n ${NAMESPACE} --timeout=60s

# Find PVC paths
echo "[4/5] Copying data to PVCs..."
DATA_PV=$(kubectl get pv -l pvcName=couchdb-data -o jsonpath='{.items[0].spec.local.path}')
ETC_PV=$(kubectl get pv -l pvcName=couchdb-etc -o jsonpath='{.items[0].spec.local.path}')

if [ -z "$DATA_PV" ] || [ -z "$ETC_PV" ]; then
    echo "Error: Could not find PVC paths"
    exit 1
fi

# Copy data
echo "Copying data..."
sudo cp -r ${COUCHDB_DATA_PATH}/* ${DATA_PV}/
sudo cp -r ${COUCHDB_ETC_PATH}/* ${ETC_PV}/

# Set permissions
sudo chown -R 1000:1000 ${DATA_PV}/
sudo chown -R 1000:1000 ${ETC_PV}/

echo "[5/5] Deploying to k3s..."
echo "=== Migration complete ==="
