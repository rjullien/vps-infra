#!/bin/bash
# Migration script: Docker monitoring stack -> Kubernetes (k3s)

set -e

NAMESPACE="monitoring"

echo "=== Monitoring Stack Migration: Docker -> k3s ==="
echo ""

# Check if Docker containers are running
echo "[1/7] Checking Docker containers..."

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
echo "[2/7] Identifying Docker volumes..."

PROMETHEUS_VOLUME=$(docker volume inspect monitoring_prometheus_data --format '{{.Mountpoint}}' 2>/dev/null || echo "")
GRAFANA_VOLUME=$(docker volume inspect monitoring_grafana_data --format '{{.Mountpoint}}' 2>/dev/null || echo "")
LOKI_VOLUME=$(docker volume inspect monitoring_loki_data --format '{{.Mountpoint}}' 2>/dev/null || echo "")
TEMPO_VOLUME=$(docker volume inspect monitoring_tempo_data --format '{{.Mountpoint}}' 2>/dev/null || echo "")

echo "  - Prometheus volume: ${PROMETHEUS_VOLUME:-not found}"
echo "  - Grafana volume: ${GRAFANA_VOLUME:-not found}"
echo "  - Loki volume: ${LOKI_VOLUME:-not found}"
echo "  - Tempo volume: ${TEMPO_VOLUME:-not found}"

# Create namespaces
echo ""
echo "[3/7] Creating Kubernetes namespaces..."
kubectl apply -f workloads/monitoring/00-namespaces.yaml

# Create InfisicalSecret for Grafana (after configuring Infisical)
echo ""
echo "[4/7] Configuring Grafana credentials via Infisical..."
echo "  NOTE: Make sure to create secrets in Infisical first!"
echo "  - Create project 'monitoring' in Infisical"
echo "  - Add secret /grafana with key 'admin-password'"
echo "  - Update projectId in workloads/monitoring/01-grafana-infisical-secret.yaml"

# Apply monitoring stack
echo ""
echo "[5/7] Applying monitoring stack via ArgoCD..."

# Apply in order: Loki first (for datasources), then Tempo, then Prometheus-stack
kubectl apply -f workloads/monitoring/loki.yaml -n ${NAMESPACE}
kubectl apply -f workloads/monitoring/tempo.yaml -n ${NAMESPACE}
kubectl apply -f workloads/monitoring/kube-prometheus-stack.yaml -n ${NAMESPACE}

# Wait for PVCs to be bound
echo ""
echo "[6/7] Waiting for PVCs to be bound..."
for pvc in prometheus-db loki tempo; do
    echo "  - Waiting for ${pvc}..."
    kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/${pvc} -n ${NAMESPACE} --timeout=120s 2>/dev/null || true
done

# Copy data from Docker volumes to PVCs
echo ""
echo "[7/7] Copying data from Docker volumes to PVCs..."

copy_volume_data() {
    local source_vol=$1
    local pvc_name=$2
    local dest_path=$3
    
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
    copy_volume_data "$PROMETHEUS_VOLUME" "prometheus-db" "/prometheus"
fi

if [ -n "$GRAFANA_VOLUME" ]; then
    copy_volume_data "$GRAFANA_VOLUME" "grafana" "/var/lib/grafana"
fi

if [ -n "$LOKI_VOLUME" ]; then
    copy_volume_data "$LOKI_VOLUME" "loki" "/var/loki"
fi

if [ -n "$TEMPO_VOLUME" ]; then
    copy_volume_data "$TEMPO_VOLUME" "tempo" "/var/tempo"
fi

echo ""
echo "=== Migration complete ==="
echo ""
echo "Next steps:"
echo "1. Configure Infisical secrets:"
echo "   - Create project 'monitoring'"
echo "   - Add secret /grafana with key 'admin-password'"
echo "   - Update projectId in workloads/monitoring/01-grafana-infisical-secret.yaml"
echo "2. Commit and push the InfisicalSecret configuration"
echo "3. Wait for ArgoCD to sync"
echo "4. Access Grafana at: https://grafana.bapttf.com"
echo "5. Access Prometheus at: https://prometheus.bapttf.com"
echo ""
echo "NOTE: Metrics history will not be preserved (Prometheus TSDB). Logs in Loki may take time to rebuild."
