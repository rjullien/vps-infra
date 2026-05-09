# GitHub Actions Runner Controller (ARC) v0.14.1

Self-hosted runners on k3s for `rjullien/ce-analytics-dashboard`.

## Architecture

| Component | Method | Namespace |
|-----------|--------|-----------|
| Controller + CRDs | ArgoCD Helm OCI (`apps/arc-controller.yaml`) | `arc-systems` |
| Namespaces + Secret | Kustomize (`system/github-actions-runner/`) | `arc-runners` |
| Runner Scale Set | Pure YAML AutoscalingRunnerSet CRD (Kustomize) | `arc-runners` |

## Usage in workflows

```yaml
jobs:
  build:
    runs-on: arc-runner-set
    steps:
      - uses: actions/checkout@v4
      - run: docker build .
```

## Setup

1. Store PAT in Infisical:
   - Project: `infrastructure` | Env: `prod` | Path: `/github-actions-runner`
   - Key: `github_token` | Value: GitHub PAT (classic) with `repo` scope

2. Merge PR → ArgoCD auto-syncs both apps

## Key design decisions

- **Controller via Helm**: Unavoidable — installs CRDs, ClusterRoles, ServiceAccount, Deployment
- **Runner set via pure YAML**: Better GitOps — ArgoCD detects changes instantly, no Helm sync issues
- **DinD sidecar**: Manual config in runner-set.yaml (not using `containerMode` which is Helm-only)
- **Version label**: `app.kubernetes.io/version: "0.14.1"` is CRITICAL — controller deletes resources without it

## Updating ARC version

1. Update `apps/arc-controller.yaml` → `targetRevision`
2. Update `runner-set.yaml` → `app.kubernetes.io/version` label
3. Push → ArgoCD syncs
