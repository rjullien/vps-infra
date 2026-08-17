---
name: daily-brief
description: "RETIRED — WhatsApp daily brief is tripkit-backend only. Do not send. Do not schedule."
user-invocable: true
---

# Daily Brief — RETIRED (OpenClaw cron forbidden)

DAILY_BRIEF_CRON_FORBIDDEN

This skill is a **no-op**. The morning WhatsApp “trucs du jour” is owned by **tripkit-backend** (`internal/dailybrief` in-process ticker → GoWA). Hermes / NullClaw / OpenClaw must not send it.

## If this skill is invoked (chat, leftover PVC cron, `/travel:daily-brief`)

1. Do **not** generate a brief.
2. Do **not** send WhatsApp (GoWA, whatsmeow, HA, CallMeBot).
3. Do **not** run `openclaw cron add`, `cron add`, or `cron edit` for daily-brief.
4. Reply in one short sentence: the OpenClaw daily-brief cron is retired; TripKit backend sends the group message. Then stop.

## Why the old cron vanished

OpenClaw jobs lived in the agent PVC, not GitOps:

- No Kubernetes `CronJob` in this repo
- `config.yaml` / `config.json` here have **no** cron jobs
- Hermes init copies GitOps `config.yaml` onto the PVC on every pod start
- A PVC-only `openclaw cron add` disappears on restart and is **not** recreated by Argo

## Do not restore it

GitOps must never add:

- a Kubernetes `CronJob` for daily-brief
- an OpenClaw / Hermes schedule that calls this skill or `/travel:daily-brief`
