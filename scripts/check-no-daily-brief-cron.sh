#!/usr/bin/env bash
# Regression: the retired OpenClaw / Hermes daily-brief cron must not come back
# via GitOps (CronJob, agent config, or a skill that sends/schedules WhatsApp).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "OK: $*"; }

MARKER="DAILY_BRIEF_CRON_FORBIDDEN"
SKILLS=(
  "$ROOT/workloads/agents/hermes-leo/skills/daily-brief/SKILL.md"
  "$ROOT/workloads/agents/nullclaw-leo/skills/daily-brief/SKILL.md"
)
TRAVEL=(
  "$ROOT/workloads/agents/hermes-leo/skills/travel/SKILL.md"
  "$ROOT/workloads/agents/nullclaw-leo/skills/travel/SKILL.md"
)
CONFIGS=(
  "$ROOT/workloads/agents/hermes-leo/config.yaml"
  "$ROOT/workloads/agents/nullclaw-leo/config.json"
)

# 1. No Kubernetes CronJob whose name/contents look like daily-brief WhatsApp.
while IFS= read -r -d '' f; do
  if grep -qiE 'kind:[[:space:]]*CronJob' "$f"; then
    if grep -qiE 'daily[-_]?brief|dailybrief|/travel:daily-brief' "$f"; then
      fail "CronJob mentions daily-brief: $f"
    fi
  fi
done < <(find "$ROOT" -type f \( -name '*.yaml' -o -name '*.yml' \) ! -path '*/.git/*' -print0)
ok "no daily-brief Kubernetes CronJob"

# 2. Retired skills must exist, be a no-op, and forbid scheduling/sending.
for f in "${SKILLS[@]}"; do
  [[ -f "$f" ]] || fail "missing $f"
  grep -q "$MARKER" "$f" || fail "$f missing $MARKER"
  grep -qiE 'no-op|RETIRED' "$f" || fail "$f must be marked RETIRED/no-op"
  grep -Fq 'Do **not** send WhatsApp' "$f" || fail "$f must forbid WhatsApp send"
  # Must not instruct creating a cron. Positive schedule examples = fail.
  if grep -qiE 'cron add job=\{' "$f"; then
    fail "$f still contains a cron-add recipe"
  fi
done
ok "daily-brief skills are retired no-ops ($MARKER)"

# 3. Travel skills must not route daily-brief to a generator / WhatsApp send.
for f in "${TRAVEL[@]}"; do
  [[ -f "$f" ]] || fail "missing $f"
  grep -q "$MARKER" "$f" || fail "$f missing $MARKER (daily-brief must stay retired)"
  if grep -qiE 'Génère le brief quotidien|Generer le brief quotidien|bmad-travel/skills/daily-brief' "$f"; then
    fail "$f still routes /travel:daily-brief to the old generator"
  fi
done
ok "travel skills do not revive /travel:daily-brief"

# 4. Committed agent configs must not schedule daily-brief.
for f in "${CONFIGS[@]}"; do
  [[ -f "$f" ]] || fail "missing $f"
  if grep -qiE 'daily[-_]?brief|dailybrief|/travel:daily-brief' "$f"; then
    fail "$f schedules or names daily-brief"
  fi
done
ok "hermes/nullclaw configs do not mention daily-brief"

# 5. Backend auto-send must stay off in GitOps (in-process worker, not a CronJob).
DEPLOY="$ROOT/workloads/tripkit-backend/deployment.yaml"
[[ -f "$DEPLOY" ]] || fail "missing $DEPLOY"
if grep -A1 'name: TRIPKIT_DAILY_BRIEF_WORKER' "$DEPLOY" | grep -q 'value: "1"'; then
  fail "TRIPKIT_DAILY_BRIEF_WORKER=1 would restart the morning WhatsApp auto-send"
fi
if ! grep -A1 'name: TRIPKIT_DAILY_BRIEF_WORKER' "$DEPLOY" | grep -q 'value: "0"'; then
  fail "tripkit-backend must pin TRIPKIT_DAILY_BRIEF_WORKER=0"
fi
ok "tripkit-backend auto worker pinned off"

echo "all checks passed"
