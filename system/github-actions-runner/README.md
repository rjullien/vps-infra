# GitHub Actions Runner Controller (ARC)

Self-hosted runners on k3s for `rjullien/ce-analytics-dashboard`.

## Architecture

3 ArgoCD Applications:
1. **github-actions-runner-base** — namespaces + Infisical secret sync
2. **arc-controller** — ARC controller (Helm OCI chart, `arc-systems` namespace)
3. **arc-runner-set** — Runner scale set (Helm OCI chart, `arc-runners` namespace)

## Usage

```yaml
jobs:
  build:
    runs-on: arc-runner-set
    steps:
      - uses: actions/checkout@v4
      - run: docker build .
```

## Setup

1. Store PAT in Infisical: project `infrastructure`, env `prod`, path `/github-actions-runner`, key `github_token`
2. Merge PR — ArgoCD auto-syncs

## Specs

- ARC v0.14.1
- DinD enabled (docker build support)
- Scale 0→3 (no idle runners)
- Runner limits: 2 CPU / 2Gi RAM
