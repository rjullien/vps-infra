# VPS Infrastructure Setup

GitOps infrastructure on k3s with ArgoCD.

## Prerequisites

- Fresh VPS with Ubuntu/Debian
- Domain pointing to your VPS
- Cloudflare account for DNS

---

## Setup Guide

### Step 1: Install k3s (without Traefik)

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable=traefik" sh
```

### Step 2: Deploy ArgoCD

```bash
kubectl apply -f https://raw.githubusercontent.com/BaptTF/vps-infra/refs/heads/main/root-app.yaml

# Get ArgoCD password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### Step 3: Install kubeseal (for SealedSecrets)

```bash
# macOS
brew install kubeseal

# Linux
# Download from https://github.com/bitnami-labs/sealed-secrets/releases
```

### Step 4: Generate SealedSecrets

#### Cloudflare credentials:
```bash
# Create API token in Cloudflare (Zone:DNS:Edit permissions)
kubectl create secret generic cloudflare-credentials \
  -n cert-manager \
  --from-literal=api-token='YOUR_API_TOKEN' \
  -o yaml | kubeseal --format yaml > workloads/infisical/02-cloudflare-secret.yaml
```

#### Infisical DB credentials:
```bash
kubectl create secret generic infisical-db-credentials \
  -n infisical \
  --from-literal=username=infisical \
  --from-literal=password='YOUR_PASSWORD' \
  -o yaml | kubeseal --format yaml > workloads/infisical/03-db-credentials.yaml
```

### Step 5: Commit and push

```bash
git add .
git commit -m "feat: add sealed secrets"
git push
```

### Step 6: Configure Infisical

1. Access `https://infisical.bapttf.com`
2. Create admin account
3. Create project `monitoring`
4. Create project `couchdb`

Add secrets:

| Project | Path | Keys |
|---------|------|------|
| monitoring | `/grafana` | `admin-password` |
| couchdb | `/couchdb` | `COUCHDB_USER`, `COUCHDB_PASSWORD` |

### Step 7: Update InfisicalSecret project IDs

Edit these files and replace `REPLACE_WITH_PROJECT_ID`:
- `workloads/obsidian-livesync/couchdb.yaml`
- `workloads/monitoring/01-grafana-infisical-secret.yaml`

```bash
git add .
git commit -m "feat: configure Infisical project IDs"
git push
```

### Step 8: Migrate data

```bash
./scripts/migrate-vaultwarden.sh
./scripts/migrate-couchdb.sh
./scripts/migrate-forgejo.sh
./scripts/migrate-monitoring.sh
```

---

## Services

| Service | URL |
|---------|-----|
| ArgoCD | https://argocd.bapttf.com |
| Grafana | https://grafana.bapttf.com |
| Prometheus | https://prometheus.bapttf.com |
| Infisical | https://infisical.bapttf.com |
| Vaultwarden | https://vault.bapttf.com |
| Forgejo | https://git.bapttf.com |
| CouchDB | https://obsidian-livesync.bapttf.com |
