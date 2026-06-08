#!/usr/bin/env bash
#
# watchdog.sh — independent dead-man's-switch for the daily ETL.
#
# Runs on its OWN schedule ~2h after the ETL cron (see .github/workflows/watchdog.yml).
# It does NOT trust the ETL run's self-reported status: the inline alarm in etl.yml
# only fires on success()/failure(), so a run cancelled by `timeout-minutes`, or one
# that never gets scheduled (GitHub disables a scheduled workflow after 60 days of
# inactivity), slips through. The watchdog instead checks the only thing that matters:
# did the pipeline publish a fresh history row today?
#
# Ground truth = the latest date in history.csv on the `status` branch. main is
# protected (PR-only), so the ETL publishes its health board — including history.csv —
# to the unprotected `status` branch; render.R upserts one row per UTC day, so
# `latest == today` means "the ETL ran AND recorded today". If not, open (or refresh)
# ONE deduped `watchdog` issue; once a fresh row lands, close it automatically.
#
# Dependencies (present on GitHub-hosted runners): gh, jq, git, coreutils date.
# Auth: GH_TOKEN in env; workflow grants `issues: write` + `actions: read`. GH_REPO
# is set in the workflow so gh resolves the repo regardless of checkout state.
#
# Self-contained and idempotent: running it twice produces no extra issues or churn
# beyond the periodic "still stale" comment.

set -euo pipefail

STATUS_BRANCH="${STATUS_BRANCH:-status}"
CSV_PATH="${CSV_PATH:-history.csv}"      # at the root of the status branch
LABEL="watchdog"
TITLE="🔴 Daily ETL watchdog: status is stale"

today="$(date -u +%F)"

# Latest published day = max valid date in history.csv on the status branch. Read it
# straight off the branch ref (authoritative, no CDN caching). Empty if the branch or
# file is missing — which itself reads as stale and (correctly) alarms.
latest=""
if git fetch --depth=1 origin "$STATUS_BRANCH" 2>/dev/null \
   && git cat-file -e "origin/${STATUS_BRANCH}:${CSV_PATH}" 2>/dev/null; then
  latest="$(git show "origin/${STATUS_BRANCH}:${CSV_PATH}" \
            | tail -n +2 | cut -d, -f1 | tr -d '"' \
            | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' | sort | tail -1 || true)"
fi

echo "watchdog: today=${today} latest_published=${latest:-<none>}"

# Best-effort context: the most recent scheduled etl run's conclusion + link.
run_line=""
if run_json="$(gh run list --workflow etl.yml --limit 1 \
      --json conclusion,status,createdAt,url 2>/dev/null)"; then
  concl="$(jq -r '.[0].conclusion // .[0].status // "unknown"' <<<"$run_json")"
  rurl="$(jq -r '.[0].url // ""' <<<"$run_json")"
  rwhen="$(jq -r '.[0].createdAt // ""' <<<"$run_json")"
  [[ -n "$rurl" ]] && run_line="Most recent \`etl\` run: **${concl}** (${rwhen}) — ${rurl}"
fi

# Ensure the dedupe label exists (non-fatal if it already does).
gh label create "$LABEL" \
    --description "Independent watchdog: ETL did not refresh the status board" \
    --color "B60205" 2>/dev/null \
  || echo "watchdog: label '$LABEL' already exists (or create skipped)."

existing="$(gh issue list --label "$LABEL" --state open \
    --json number,title \
    --jq "map(select(.title == \"${TITLE}\")) | .[0].number // empty")"

if [[ -n "$latest" && "$latest" == "$today" ]]; then
  # Fresh: the pipeline published today. Close any open watchdog alarm.
  if [[ -n "$existing" ]]; then
    echo "watchdog: status fresh again (${today}) — closing #${existing}."
    gh issue close "$existing" \
      --comment "Resolved: \`history.csv\` on the \`status\` branch advanced to ${today}; the ETL published a fresh row. Closing automatically." \
      || echo "watchdog: close of #${existing} failed (non-fatal)." >&2
  else
    echo "watchdog: status fresh (${today}) — nothing to do."
  fi
  exit 0
fi

# Stale: no row for today ~2h after the scheduled run. Alarm.
body="$(printf '%s\n' \
  "The daily ETL has **not published fresh status today** (\`${today}\`)." \
  "" \
  "| check | value |" \
  "| --- | --- |" \
  "| today (UTC) | \`${today}\` |" \
  "| latest published day | \`${latest:-<none>}\` |" \
  "" \
  "${run_line}" \
  "" \
  "The watchdog runs ~2h after the ETL cron and checks the one thing that matters:" \
  "did \`history.csv\` on the \`status\` branch gain a row for today. It hasn't — so the" \
  "run is missing, **cancelled** (e.g. it hit \`timeout-minutes\`), or failed before the" \
  "publish step. The inline ETL alarm only fires on success/failure, so a cancellation" \
  "or a never-scheduled run slips through; this watchdog is the independent backstop." \
  "" \
  "_Opened automatically; closes itself once a fresh \`history.csv\` row lands._")"

if [[ -n "$existing" ]]; then
  echo "watchdog: still stale — refreshing #${existing}."
  gh issue comment "$existing" \
    --body "Still stale as of ${today} (latest published: \`${latest:-<none>}\`). ${run_line}" \
    || echo "watchdog: comment on #${existing} failed (non-fatal)." >&2
else
  echo "watchdog: opening stale-status issue."
  gh issue create --title "$TITLE" --label "$LABEL" --body "$body" \
    || echo "watchdog: create failed (non-fatal)." >&2
fi

echo "watchdog: done."
