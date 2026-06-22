#!/usr/bin/env bash
# scripts/healthcheck-nightly.sh
#
# Watchdog for the nightly build pipeline.
# Runs every 30 minutes via cron. If the most recent successful build is
# older than MAX_AGE_HOURS, write .last-build-failed and (best-effort) post
# a Discord alert so the failure isn't silent.
#
# Cron:
#   */30 * * * * /home/x2/xkg-releases/scripts/healthcheck-nightly.sh \
#                 >> /home/x2/xkg-releases/healthcheck.log 2>&1
#
# Exit codes:
#   0 = healthy (build recent OR failure already reported)
#   1 = new failure detected (and reported)

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HEARTBEAT="$ROOT/.last-build-success"
FLAG="$ROOT/.last-build-failed"
LOG="$ROOT/healthcheck.log"
MAX_AGE_HOURS="${MAX_AGE_HOURS:-26}"   # 26h = daily cadence + 2h slack
ALERT_COOLDOWN_MIN="${ALERT_COOLDOWN_MIN:-360}"  # don't spam: 6h between alerts
DISCORD_NOTIFY="${DISCORD_NOTIFY:-/home/x2/.openclaw/workspace/scripts/discord-notify.sh}"
DISCORD_WEBHOOK="${DISCORD_WEBHOOK:-}"  # set via env if you want alerts
HOST="$(hostname -s 2>/dev/null || echo unknown)"

ts()  { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
log() { printf '[%s] %s\n' "$(ts)" "$*" ; }

# age of heartbeat (seconds since epoch). 0 if missing/unreadable.
hb_age() {
  [ -f "$HEARTBEAT" ] || { echo 99999999; return; }
  # first line is the ISO timestamp from date -u
  line="$(head -n1 "$HEARTBEAT" 2>/dev/null || true)"
  [ -n "$line" ] || { echo 99999999; return; }
  hb_epoch="$(date -u -d "$line" +%s 2>/dev/null || echo 0)"
  [ "$hb_epoch" -gt 0 ] || { echo 99999999; return; }
  now="$(date -u +%s)"
  echo $(( now - hb_epoch ))
}

# age of alert flag (seconds), so we can apply cooldown
flag_age() {
  [ -f "$FLAG" ] || { echo 99999999; return; }
  ft="$(stat -c %Y "$FLAG" 2>/dev/null || echo 0)"
  now="$(date -u +%s)"
  echo $(( now - ft ))
}

log "healthcheck start (host=$HOST max_age=${MAX_AGE_HOURS}h)"

age="$(hb_age)"
max_age_s=$(( MAX_AGE_HOURS * 3600 ))

if [ "$age" -le "$max_age_s" ]; then
  log "healthy: last build was ${age}s ago (limit ${max_age_s}s)"
  # success path: if a stale flag is around, clear it
  if [ -f "$FLAG" ]; then
    rm -f "$FLAG"
    log "cleared stale failure flag"
  fi
  exit 0
fi

# failure path
log "UNHEALTHY: last build was ${age}s ago (>${max_age_s}s)"
date -u '+%Y-%m-%dT%H:%M:%SZ' > "$FLAG"
echo "host=$HOST"      >> "$FLAG"
echo "age_seconds=$age" >> "$FLAG"
echo "max_age_hours=$MAX_AGE_HOURS" >> "$FLAG"
log "wrote $FLAG"

# cooldown so we don't spam every 30 minutes
cooldown_s=$(( ALERT_COOLDOWN_MIN * 60 ))
fa="$(flag_age)"
if [ "$fa" -lt "$cooldown_s" ]; then
  log "alert suppressed: previous alert was ${fa}s ago (<${cooldown_s}s cooldown)"
  exit 1
fi

# best-effort alert
msg="⚠️ xkg nightly-build is stale on \`$HOST\`. Last successful build was ${age}s ago (limit ${max_age_s}s). Check \`$ROOT/nightly-build.log\` and run \`bash $ROOT/scripts/nightly-build.sh\` to recover."
if [ -x "$DISCORD_NOTIFY" ] && [ -n "$DISCORD_WEBHOOK" ]; then
  log "sending Discord alert"
  "$DISCORD_NOTIFY" "$DISCORD_WEBHOOK" "$msg" "xkg-nightly-watchdog" >> "$LOG" 2>&1 || true
elif [ -x "$DISCORD_NOTIFY" ]; then
  log "DISCORD_WEBHOOK not set — skipping alert (would have sent: $msg)"
else
  log "no alert tool available — failure only visible via $FLAG and $LOG"
fi

exit 1