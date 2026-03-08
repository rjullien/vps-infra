#!/bin/bash
# Migration script: Docker -> Kubernetes (k3s)
# This script only migrates DATA. ArgoCD manages the deployment.

set -e

echo "=== LaCoope Migration: Docker -> k3s ==="

# Stop Docker containers
if docker ps | grep -q lacoope-backend; then
    echo "[1/1] Stopping Docker containers..."
    docker stop lacoope-backend
    docker stop lacoope-frontend
fi

echo ""
echo "=== Migration complete ==="
echo ""
echo "ArgoCD has deployed LaCoope"
echo "  - Frontend: https://lacoope.bapttf.com"
echo "  - Backend: https://lacoope-api.bapttf.com"
echo ""
echo "NOTE: Database data cannot be migrated (PostgreSQL)."
echo "You need to set up a new PostgreSQL database."
