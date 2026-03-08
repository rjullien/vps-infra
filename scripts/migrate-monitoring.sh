#!/bin/bash
# Migration script: Docker monitoring stack -> Kubernetes (k3s)
# This script only migrates DATA. ArgoCD manages the deployment.

set -e

NAMESPACE="monitoring"

echo "=== Monitoring Stack Migration: Docker -> k3s ==="
echo ""

# Check if Docker containers are running
echo "[1/4] Stopping Docker monitoring containers..."

if docker ps | grep -q prometheus; then
    echo "  - Stopping prometheus..."
    docker stop prometheus 2>/dev/null || true
fi

if docker ps | grep -q grafana; then
    echo "  - Stopping grafana..."
    docker stop grafana 2>/dev/null || true
fi

if docker ps | grep -q loki; then
    echo "  - Stopping loki..."
    docker stop loki 2>/dev/null || true
fi

if docker ps | grep -q tempo; then
    echo "  - Stopping tempo..."
    docker stop tempo 2>/dev/null || true
fi

# Get volume paths
echo ""
echo "[2/4] Identifying Docker volumes..."

PROMETHEUS_VOLUME=$(docker volume inspect monitoring_prometheus_data --format '{{.Mountpoint}}' 2>/dev/null || echo "")
GRAFANA_VOLUME=$(docker volume inspect monitoring_grafana_data --format '{{.Mountpoint}}' 2>/dev/null || echo "")
LOKI_VOLUME=$(docker volume inspect monitoring_loki_data --format '{{.Mountpoint}}' 2>/dev/null || echo "")
TEMPO_VOLUME=$(docker volume inspect monitoring_tempo_data --format '{{.Mountpoint}}' 2>/dev/null || echo "")

echo "  - Prometheus volume: ${PROMETHEUS_VOLUME:-not found}"
echo "  - Grafana volume: ${GRAFANA_VOLUME:-not found}"
echo "  - Loki volume: ${LOKI_VOLUME:-not found}"
echo "  - Tempo volume: ${TEMPO_VOLUME:-not found}"

# Wait for PVCs to be ready
echo ""
echo "[3/4] Waiting for PVCs to be bound (ArgoCD should have created them)..."

for pvc in prometheus-db loki tempo; do
    echo "  - Waiting for ${pvc}..."
    kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/${pvc} -n ${NAMESPACE} --timeout=180s 2>/dev/null || echo "    WARNING: ${pvc} not found or not bound"
done

# Copy data from Docker volumes to PVCs
echo ""
echo "[4/4] Copying data from Docker volumes to PVCs..."

copy_volume_data() {
    local source_vol=$1
    local pvc_name=$2
    
    if [ -z "$source_vol" ]; then
        echo "  - ${pvc_name}: source volume not found, skipping..."
        return
    fi
    
    # Get PV path
    local pv_path=$(kubectl get pv -l pvcName=${pvc_name} -o jsonpath='{.items[0].spec.local.path}' 2>/dev/null || echo "")
    
    if [ -z "$pv_path" ]; then
        echo "  - ${pvc_name}: could not find PV path, skipping..."
        return
    fi
    
    echo "  - Copying ${pvc_name}: ${source_vol} -> ${pv_path}"
    sudo cp -r ${source_vol}/* ${pv_path}/ 2>/dev/null || true
    sudo chown -R 1000:1000 ${pv_path}/ 2>/dev/null || true
}

# Copy data for each component
if [ -n "$PROMETHEUS_VOLUME" ]; then
    copy_volume_data "$PROMETHEUS_VOLUME" "prometheus-db"
fi

if [ -n "$GRAFANA_VOLUME" ]; then
    copy_volume_data "$GRAFANA_VOLUME" "grafana"
fi

if [ -n "$LOKI_VOLUME" ]; then
    copy_volume_data "$LOKI_VOLUME" "loki"
fi

if [ -n "$TEMPO_VOLUME" ]; then
    copy_volume_data "$TEMPO_VOLUME" "tempo"
fi

echo ""
echo "=== Migration complete ==="
echo ""
echo "ArgoCD has deployed:"
echo "  - Prometheus: https://prometheus.bapttf.com"
echo "  - Grafana: https://grafana.bapttf.com"
echo "  - Loki: Integrated in Grafana"
echo "  - Tempo: Integrated in Grafana"
echo ""
echo "NOTE: Prometheus TSDB metrics cannot be migrated (incompatible format)."
echo "Logs in Loki may need time to rebuild."
