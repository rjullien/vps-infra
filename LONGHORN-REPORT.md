# Longhorn Storage + Léa HA Migration — Rapport pour opencode

## Contexte

Le pod OpenClaw (Léa) tourne sur le VPS avec un PVC `local-path` de 10 Gi.
Le VPS est serré en RAM (5.2 GB used / 7.9 GB total). Un worker node (bapt-debian) est disponible via Tailscale avec ~4.3 GB RAM libre.

**Objectif :** Permettre au pod Léa de tourner sur le worker node en temps normal, avec failback automatique sur le VPS si le worker tombe — sans perte de données.

**Solution :** Installer Longhorn comme CSI distribué, migrer le PVC de Léa dessus, et garder les PVC des DB sur `local-path`.

---

## Architecture cible

```
Normal (worker preferred):
┌─────────────────────────┐         ┌─────────────────────────┐
│      bapt-debian        │  async  │         VPS             │
│      (worker)           │ ──────► │       (control)         │
│                         │ replica │                         │
│  [Pod Léa] ◄──► PVC RW │         │  PVC replica (standby)  │
│                         │         │                         │
│  Longhorn engine active │         │  Longhorn replica only  │
└─────────────────────────┘         └─────────────────────────┘
        ~21ms latency via Tailscale

Failover (worker down):
                                    ┌─────────────────────────┐
                                    │         VPS             │
                                    │                         │
                                    │  [Pod Léa] ◄──► PVC RW │
                                    │                         │
                                    │  Longhorn engine active │
                                    └─────────────────────────┘
                                    k8s reschedules automatically
```

---

## ⚠️ Règle critique : Longhorn UNIQUEMENT pour les workloads non-DB

Les bases de données (CloudNative-PG, forgejo embedded, etc.) gèrent leur propre réplication.
Mettre Longhorn en dessous = double réplication + risque de corruption (write ordering).

| Workload | StorageClass | Raison |
|----------|-------------|--------|
| `postgres-cluster` (CNPG) | `local-path` ❌ pas Longhorn | Réplication PG native |
| Forgejo | `local-path` ❌ | DB intégrée |
| Vaultwarden | `local-path` ❌ | DB SQLite, single node OK |
| Obsidian LiveSync | `local-path` ❌ | CouchDB, syncs at app level |
| Meilisearch | `local-path` ❌ | Search index, rebuildable |
| MinIO | `local-path` ❌ | Object store, single instance |
| **OpenClaw (Léa)** | **`longhorn` ✅** | Workspace/config files, needs HA |
| **Nullclaw/Nullclaw-Leo** | **`longhorn` ✅** | Same pattern, agents need HA |
| **Voyage-app** | `longhorn` ✅ (optionnel) | Si besoin de HA |

**Implémentation :** Ne PAS changer le `defaultStorageClass`. Longhorn est opt-in via `storageClassName: longhorn` explicite dans les PVC concernés.

---

## 1. Installer Longhorn

### `apps/longhorn.yaml` (ArgoCD Application)
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: longhorn
  namespace: argocd
spec:
  project: system
  source:
    repoURL: https://charts.longhorn.io
    chart: longhorn
    targetRevision: 1.7.3
    helm:
      valuesObject:
        # ── Tuning pour cluster 2 nœuds, RAM limitée ──
        defaultSettings:
          # 2 replicas = 1 sur chaque nœud (HA bidirectionnelle)
          defaultReplicaCount: 2
          # Rebuild auto quand un nœud revient
          replicaAutoBalance: best-effort
          # Pas de snapshot auto (on gère manuellement si besoin)
          snapshotDataIntegrityCronjob: ""
          # Garder les replicas même si un nœud est down temporairement
          nodeDownPodDeletionPolicy: delete-both-statefulset-and-deployment-pod
          # Concurrency limité pour ne pas saturer le réseau Tailscale
          concurrentReplicaRebuildPerNodeLimit: 1
          # Pas de backup auto S3 (pas de S3 configuré)
          backupTarget: ""
          # Timeout pour détacher un volume d'un nœud down (secondes)
          # 3 min = compromis entre détection rapide et faux positifs
          nodeDrainPolicy: allow-if-replica-is-stopped
        
        # ── Instance manager allégé ──
        longhornManager:
          resources:
            requests:
              cpu: 10m
              memory: 64Mi
            limits:
              cpu: 500m
              memory: 256Mi
        
        longhornDriver:
          resources:
            requests:
              cpu: 10m
              memory: 32Mi
            limits:
              cpu: 250m
              memory: 128Mi
        
        longhornUI:
          # UI accessible via Tailscale uniquement (debug)
          replicas: 1
          resources:
            requests:
              cpu: 5m
              memory: 16Mi
            limits:
              cpu: 100m
              memory: 64Mi

        # ── Storage path ──
        defaultSettings:
          defaultDataPath: /var/lib/longhorn
        
        # ── Ne PAS devenir le default StorageClass ──
        persistence:
          defaultClass: false
          defaultClassReplicaCount: 2
        
        # ── CSI settings ──
        csi:
          attacherReplicaCount: 1
          provisionerReplicaCount: 1
          resizerReplicaCount: 1
          snapshotterReplicaCount: 1
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: longhorn-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### Prérequis sur les 2 nœuds
```bash
# Sur VPS et bapt-debian
apt install -y open-iscsi nfs-common
systemctl enable --now iscsid
```

Longhorn a besoin d'iSCSI pour le block storage. Vérifier avec :
```bash
systemctl status iscsid
```

---

## 2. Migrer le PVC de Léa

### Étape 1 — Créer le nouveau PVC Longhorn

Modifier `workloads/agents/openclaw/openclaw-pvc.yaml` :
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: openclaw-home-pvc
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: longhorn
  resources:
    requests:
      storage: 10Gi
```

### Étape 2 — Migration des données

**⚠️ La migration nécessite un downtime de Léa (~5-10 min).** Procédure :

```bash
# 1. Scale down Léa
kubectl scale deployment openclaw --replicas=0 -n agents

# 2. Créer un PVC temporaire Longhorn
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: openclaw-home-pvc-longhorn
  namespace: agents
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: longhorn
  resources:
    requests:
      storage: 10Gi
EOF

# 3. Job de copie (monte les 2 PVC, rsync)
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: migrate-lea-pvc
  namespace: agents
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: migrate
          image: alpine:3.21
          command: ["sh", "-c"]
          args:
            - |
              apk add --no-cache rsync
              echo "Starting migration..."
              rsync -avP --delete /old/ /new/
              echo "Migration complete. Files copied:"
              du -sh /new/
          volumeMounts:
            - name: old-pvc
              mountPath: /old
              readOnly: true
            - name: new-pvc
              mountPath: /new
      volumes:
        - name: old-pvc
          persistentVolumeClaim:
            claimName: openclaw-home-pvc
        - name: new-pvc
          persistentVolumeClaim:
            claimName: openclaw-home-pvc-longhorn
EOF

# 4. Attendre la fin du job
kubectl wait --for=condition=complete job/migrate-lea-pvc -n agents --timeout=600s
kubectl logs job/migrate-lea-pvc -n agents

# 5. Swap les PVC
kubectl delete pvc openclaw-home-pvc -n agents
# Renommer le nouveau PVC (il faut delete + recreate avec le bon nom)
# OU modifier le deployment pour pointer vers openclaw-home-pvc-longhorn

# 6. Scale up Léa
kubectl scale deployment openclaw --replicas=1 -n agents

# 7. Cleanup
kubectl delete job migrate-lea-pvc -n agents
```

**Alternative plus simple :** Modifier le nom du PVC dans le deployment pour pointer vers `openclaw-home-pvc-longhorn` directement, sans renommage.

Modifier `workloads/agents/openclaw/openclaw-deployment.yaml` :
```yaml
      volumes:
        - name: openclaw-home
          persistentVolumeClaim:
            claimName: openclaw-home-pvc-longhorn  # nouveau PVC Longhorn
```

Puis supprimer l'ancien PVC `local-path` quand tout est validé.

---

## 3. Node affinity — Préférer le worker, fallback VPS

Modifier `workloads/agents/openclaw/openclaw-deployment.yaml`, ajouter dans `spec.template.spec` :

```yaml
    spec:
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              preference:
                matchExpressions:
                  - key: kubernetes.io/hostname
                    operator: In
                    values: ["bapt-debian"]
      # Pod priority élevée pour être le dernier évincé
      priorityClassName: critical-agent
      containers:
        # ... (inchangé)
```

### PriorityClass à créer

Ajouter `system/longhorn/priority-class.yaml` (ou dans un endroit commun) :
```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: critical-agent
value: 1000000
globalDefault: false
preemptionPolicy: PreemptLowerPriority
description: "Critical agent pods — last to be evicted, can preempt lower priority"
```

---

## 4. Monitoring Longhorn (optionnel mais recommandé)

### UI accessible via Tailscale

```yaml
# system/longhorn/longhorn-ingress-tailscale.yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: longhorn-ui
  namespace: longhorn-system
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`longhorn.bapttf.com`)
      kind: Rule
      services:
        - name: longhorn-frontend
          port: 80
  tls: {}
```

Ou simplement via `kubectl port-forward` quand besoin :
```bash
kubectl port-forward svc/longhorn-frontend 8080:80 -n longhorn-system
```

---

## 5. Estimation ressources Longhorn

Sur un cluster 2 nœuds avec les settings allégés :

| Composant | Par nœud | Total |
|-----------|----------|-------|
| longhorn-manager | ~100-150 MB | ~300 MB |
| longhorn-driver | ~50 MB | ~100 MB |
| longhorn-ui | ~30 MB (1 replica) | ~30 MB |
| instance-manager (par volume) | ~30 MB | ~60 MB |
| **Total estimé** | | **~500 MB** |

Réparti sur 2 nœuds, ça fait ~250 MB par nœud. Acceptable vu les 4.3 GB dispo sur le worker.

---

## 6. Ordre de déploiement

1. **Prérequis** — Installer `open-iscsi` sur les 2 nœuds
2. **Longhorn** — Push `apps/longhorn.yaml` → ArgoCD déploie
3. **Vérifier** — `kubectl get sc` doit montrer `longhorn` (mais PAS default)
4. **PriorityClass** — Créer la PriorityClass `critical-agent`
5. **Migration PVC** — Exécuter la procédure de migration (section 2)
6. **Node affinity** — Mettre à jour le deployment Léa (section 3)
7. **Valider** — Le pod Léa doit être sur `bapt-debian` avec le volume Longhorn
8. **Test failover** — `kubectl drain bapt-debian` → vérifier que Léa reschedule sur VPS
9. **Cleanup** — Supprimer l'ancien PVC `local-path` après validation

---

## 7. Checklist

- [ ] `apt install open-iscsi nfs-common` sur VPS
- [ ] `apt install open-iscsi nfs-common` sur bapt-debian
- [ ] `systemctl enable --now iscsid` sur les 2 nœuds
- [ ] Créer `apps/longhorn.yaml` (Helm chart ArgoCD)
- [ ] Vérifier Longhorn UP : `kubectl get pods -n longhorn-system`
- [ ] Vérifier StorageClass : `kubectl get sc` → `longhorn` présent, PAS default
- [ ] Créer PriorityClass `critical-agent`
- [ ] Scale down Léa (`replicas: 0`)
- [ ] Créer PVC Longhorn + Job migration rsync
- [ ] Vérifier données copiées (logs du job)
- [ ] Mettre à jour deployment Léa (nouveau PVC + affinity + priorityClass)
- [ ] Scale up Léa → vérifier qu'elle tourne sur `bapt-debian`
- [ ] Test failover : drain worker → Léa reschedule sur VPS
- [ ] Uncordon worker → Léa revient sur `bapt-debian`
- [ ] Supprimer ancien PVC `local-path`
- [ ] (Optionnel) Migrer nullclaw/nullclaw-leo sur Longhorn aussi

---

## 8. Fichiers à créer/modifier dans vps-infra

```
vps-infra/
├── apps/
│   └── longhorn.yaml                      # NEW — ArgoCD Application (Helm)
├── system/
│   └── longhorn/                          # NEW (optionnel, pour extras)
│       ├── priority-class.yaml            # PriorityClass critical-agent
│       └── longhorn-ingress-tailscale.yaml # UI (optionnel)
└── workloads/
    └── agents/
        └── openclaw/
            ├── openclaw-deployment.yaml    # EDIT — affinity + priorityClass + PVC name
            └── openclaw-pvc.yaml           # EDIT — storageClassName: longhorn
```

---

## 9. Rollback plan

Si Longhorn pose problème :
1. Scale down Léa
2. Rsync inverse : Longhorn PVC → nouveau local-path PVC
3. Revert deployment vers PVC `local-path`
4. Scale up Léa
5. Désinstaller Longhorn si nécessaire

Le tout prend ~10 min. Les données sont toujours safe car on garde l'ancien PVC local-path tant que la migration n'est pas validée.
