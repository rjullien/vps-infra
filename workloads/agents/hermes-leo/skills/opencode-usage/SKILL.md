---
name: opencode-usage
description: Suivi de consommation OpenCode Go — affiche les quotas rolling 5h, weekly et monthly pour toutes les clés API configurées. Utiliser quand un utilisateur demande sa conso, ses quotas, ses limites OpenCode, ou veut savoir s'il reste du budget.
user-invocable: true
---

# OpenCode Go — Suivi de consommation

Interroge l'API `GET https://opencode.ai/zen/go/v1/usage` pour chaque clé API Go configurée et affiche les quotas serveur (rolling 5h / weekly / monthly).

## Quand utiliser ce skill

- L'utilisateur demande sa consommation OpenCode Go
- L'utilisateur veut savoir combien il lui reste de budget
- L'utilisateur dit "quota", "usage", "conso", "limites", "opencode"
- Alerte proactive si un seuil est dépassé (via cron)

## Variables d'environnement requises

| Variable | Description |
|----------|-------------|
| `OPENCODE_GO_API_KEY` | Clé API Go principale (Baptiste) |
| `OPENCODE_GO_API_KEY_R` | Clé API Go René (optionnelle) |
| `OPENCODE_GO_API_KEY_A` | Clé API Go A (optionnelle) |
| `OPENCODE_GO_API_KEY_N` | Clé API Go N (optionnelle) |

Les clés sont gérées dans Infisical (path `/agents/nullclaw-leo`). Si une variable n'est pas définie ou vide, l'ignorer silencieusement.

## Workflow

### 1. Appeler l'API usage pour chaque clé

```bash
curl -s -f \
  -H "Authorization: Bearer ${OPENCODE_GO_API_KEY}" \
  https://opencode.ai/zen/go/v1/usage
```

Répéter pour chaque clé définie : `OPENCODE_GO_API_KEY`, `OPENCODE_GO_API_KEY_R`, `OPENCODE_GO_API_KEY_A`, `OPENCODE_GO_API_KEY_N`.

**Mapping des noms :**
- `OPENCODE_GO_API_KEY` → "Baptiste"
- `OPENCODE_GO_API_KEY_R` → "René"
- `OPENCODE_GO_API_KEY_A` → "A"
- `OPENCODE_GO_API_KEY_N` → "N"

### 2. Parser la réponse JSON

Structure attendue (peut varier — adapter si le format diffère) :

```json
{
  "rolling5h": { "usageDollars": 2.34, "limitDollars": 12, "usagePercent": 19.5, "resetInSec": 7200 },
  "weekly":    { "usageDollars": 8.91, "limitDollars": 30, "usagePercent": 29.7, "resetInSec": 345600 },
  "monthly":   { "usageDollars": 15.00, "limitDollars": 60, "usagePercent": 25.0, "resetInSec": 1414800 }
}
```

Si le format réel diffère, adapter le parsing. Les champs importants :
- Pourcentage d'utilisation par fenêtre
- Temps avant reset (en secondes → convertir en durée lisible)
- Montant utilisé vs limite

### 3. Formater le message

Pour chaque clé, produire un bloc comme :

```
📊 OpenCode Go — Baptiste
⏱ Rolling 5h :  19% ($2.34 / $12)  — reset dans 2h00
📅 Weekly :      30% ($8.91 / $30)  — reset dans 4j 0h
🗓 Monthly :     25% ($15.00 / $60) — reset dans 26j 6h
```

**Indicateurs visuels :**
- 🟢 < 70% → tout va bien
- 🟡 70–89% → attention
- 🔴 ≥ 90% → alerte

### 4. Envoyer le résultat

Répondre directement dans la conversation (Telegram).

Si plusieurs clés sont définies, regrouper les résultats dans un seul message avec un bloc par clé, séparés par une ligne vide.

## Dashboard web

Un dashboard web est aussi disponible à `https://opencode.bapttf.com` (protégé par Authelia). Mentionner le lien si l'utilisateur veut un suivi visuel continu.

## Gestion des erreurs

| Erreur | Action |
|--------|--------|
| HTTP 401/403 | "❌ Clé [nom] invalide ou expirée — vérifier dans Infisical" |
| HTTP 429 | "⏳ Rate-limit atteint pour [nom] — réessayer dans quelques minutes" |
| Timeout / réseau | "🌐 OpenCode API injoignable — réessayer plus tard" |
| Variable non définie | Ignorer cette clé silencieusement |

## Mode alerte (cron)

Programmer un cron pour vérifier les quotas régulièrement et alerter si un seuil est dépassé :

```
cron add job={
  name: "opencode-usage-alert",
  schedule: { kind: "cron", expr: "0 */2 * * *", tz: "Europe/Paris" },
  payload: { kind: "agentTurn", message: "Vérifie les quotas OpenCode Go. Si un quota est ≥ 80%, envoie une alerte dans ma conversation privée. Sinon, ne dis rien." },
  sessionTarget: "isolated",
  delivery: { mode: "none" }
}
```

**Seuil d'alerte par défaut : 80%**

Format alerte :
```
⚠️ OpenCode Go — [Nom]
Rolling 5h à 85% ! Reset dans 1h30.
```

## Commandes rapides

| Commande | Action |
|----------|--------|
| `/opencode-usage` | Affiche les quotas de toutes les clés |
| `/opencode-usage baptiste` | Quotas d'une seule clé |
| `/opencode-usage alert on` | Active le cron d'alerte (toutes les 2h) |
| `/opencode-usage alert off` | Désactive le cron d'alerte |

## Règles

- **Lecture seule** — ce skill ne modifie rien, il interroge uniquement l'API
- Ne jamais afficher la clé API dans un message (même partiellement)
- Si toutes les clés sont undefined → répondre "Aucune clé OpenCode Go configurée. Ajouter OPENCODE_GO_API_KEY dans Infisical (path /agents/nullclaw-leo)."
- Durées lisibles : "2h30", "4j 12h", "26j 6h" (pas de secondes brutes)
