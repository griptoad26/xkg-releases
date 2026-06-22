#!/usr/bin/env bash
# scripts/nightly-build.sh
#
# Recurring nightly rebuild for the XKG public downloads.
#
# What it does:
#   1. Acquire an exclusive lock (don't run two at once).
#   2. Snapshot the current checksums of /home/x2/xkg-releases/v<VER>/.
#   3. Run the existing scripts/build.sh to refresh the release tree from the
#      builders on this host.
#   4. Regenerate checksums via build.sh (it does that already) and re-verify
#      with scripts/verify-checksums.sh.
#   5. Compare new vs old checksums; if any binary actually changed, bounce
#      the xkg-gate server so the new file handles / size are picked up
#      cleanly.
#   6. Write a heartbeat (.last-build-success) so the watchdog can detect
#      silent failures.
#
# Why this exists:
#   The gate at :9095 serves binaries straight from /home/xkg-releases/v0.1.0.
#   If the binaries there go stale, public download links ship dead code.
#   This script + cron = guaranteed daily refresh, even when the user is
#   offline. GitHub Actions runs the same matrix 1h earlier as defense in
#   depth; this script is the host-local fallback and the one that
#   updates the on-disk artifacts the gate actually serves.
#
# Usage:
#   bash scripts/nightly-build.sh                    # uses VER=0.1.0
#   VER=0.2.0 bash scripts/nightly-build.sh          # future version
#   bash scripts/nightly-build.sh --skip-gate        # don't restart gate
#
# Cron (already installed by this same task):
#   0 3 * * * /home/x2/xkg-releases/scripts/nightly-build.sh \
#             >> /home/x2/xkg-releases/nightly-build.log 2>&1
#
# Exit codes:
#   0 = success (build + verify + optional gate restart all OK)
#   1 = general failure
#   2 = build.sh failed
#   3 = verify-checksums.sh failed
#   4 = gate restart failed (build itself was OK)

set -uo pipefail

# ── args & config ──
SKIP_GATE=0
for arg in "$@"; do
  case "$arg" in
    --skip-gate) SKIP_GATE=1 ;;
    -h|--help)
      sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "unknown arg: $arg" >&2; exit 1 ;;
  esac
done

VER="${VER:-0.1.0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/v$VER"
LOG="$ROOT/nightly-build.log"
HEARTBEAT="$ROOT/.last-build-success"
LOCK="$ROOT/.nightly-build.lock"
GATE_CWD="/home/x2/xkg-gate"
GATE_CMD="python3 server.py"
GATE_PORT=9095

mkdir -p "$ROOT"

ts()  { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
log() { printf '[%s] %s\n' "$(ts)" "$*" ; }
die() { log "FATAL: $*"; exit "${2:-1}"; }

# ── lock (don't pile up runs) ──
exec 9>"$LOCK"
if ! flock -n 9; then
  log "another nightly-build.sh is already running (lock=$LOCK). exiting."
  exit 0
fi

log "========== nightly build start (ver=$VER) =========="

# ── snapshot current checksums (for change detection) ──
SNAPSHOT_BEFORE="$ROOT/.checksums-before.sha256"
SNAPSHOT_AFTER="$ROOT/.checksums-after.sha256"
: > "$SNAPSHOT_BEFORE"
if [ -f "$OUT/ALL_CHECKSUMS.sha256" ]; then
  cp -f "$OUT/ALL_CHECKSUMS.sha256" "$SNAPSHOT_BEFORE"
  log "snapshot-before: $(wc -l < "$SNAPSHOT_BEFORE") lines"
else
  log "no prior ALL_CHECKSUMS.sha256 — this is a first run"
fi

# ── the actual build (parallelize build.sh work if it ever supports it;
#    for now it's already sequential but very fast because it's just
#    cp+rename from the builders' target/ trees) ──
log "running scripts/build.sh $VER"
if ! bash "$ROOT/scripts/build.sh" "$VER" >> "$LOG" 2>&1; then
  log "ERROR: build.sh exited non-zero"
  log "========== nightly build FAILED (build.sh) =========="
  exit 2
fi
log "build.sh OK"

# ── verify ──
log "running scripts/verify-checksums.sh $VER"
if ! bash "$ROOT/scripts/verify-checksums.sh" "$VER" >> "$LOG" 2>&1; then
  log "ERROR: verify-checksums.sh exited non-zero"
  log "========== nightly build FAILED (verify) =========="
  exit 3
fi
log "verify-checksums.sh OK"

# ── snapshot after ──
if [ -f "$OUT/ALL_CHECKSUMS.sha256" ]; then
  cp -f "$OUT/ALL_CHECKSUMS.sha256" "$SNAPSHOT_AFTER"
  log "snapshot-after: $(wc -l < "$SNAPSHOT_AFTER") lines"
else
  : > "$SNAPSHOT_AFTER"
  log "WARN: no ALL_CHECKSUMS.sha256 after build"
fi

# ── did anything change? ──
CHANGED=0
if ! cmp -s "$SNAPSHOT_BEFORE" "$SNAPSHOT_AFTER"; then
  CHANGED=1
  log "binaries CHANGED since last run"
  diff "$SNAPSHOT_BEFORE" "$SNAPSHOT_AFTER" | head -40 || true
else
  log "no binary changes detected (freshness confirmed, no restart needed)"
fi

# ── restart the gate if anything changed (and we weren't told to skip) ──
if [ "$CHANGED" -eq 1 ] && [ "$SKIP_GATE" -eq 0 ]; then
  log "restarting xkg-gate on :$GATE_PORT"
  GATE_PID="$(pgrep -f "python3 server.py" | head -1 || true)"
  if [ -n "$GATE_PID" ]; then
    log "killing gate pid=$GATE_PID"
    if kill "$GATE_PID" 2>/dev/null; then
      # wait up to ~5s for it to die
      for _ in 1 2 3 4 5; do
        kill -0 "$GATE_PID" 2>/dev/null || break
        sleep 1
      done
      kill -0 "$GATE_PID" 2>/dev/null && kill -9 "$GATE_PID" 2>/dev/null || true
    fi
  else
    log "no existing gate process found"
  fi

  # relaunch in background, detached from this shell + cron
  if [ -d "$GATE_CWD" ]; then
    log "launching new gate from $GATE_CWD"
    (
      cd "$GATE_CWD" || exit 1
      nohup $GATE_CMD >> "$ROOT/gate.log" 2>&1 &
      disown || true
    )
    sleep 1
    NEW_PID="$(pgrep -f "python3 server.py" | head -1 || true)"
    if [ -n "$NEW_PID" ]; then
      log "gate restarted, new pid=$NEW_PID"
    else
      log "ERROR: gate restart did not produce a new pid"
      log "========== nightly build FAILED (gate restart) =========="
      exit 4
    fi
  else
    log "WARN: $GATE_CWD not found; skipping gate restart"
  fi
elif [ "$CHANGED" -eq 1 ] && [ "$SKIP_GATE" -eq 1 ]; then
  log "changes detected but --skip-gate given; gate left running"
fi

# ── heartbeat ──
date -u '+%Y-%m-%dT%H:%M:%SZ' > "$HEARTBEAT"
echo "ver=$VER"        >> "$HEARTBEAT"
echo "changed=$CHANGED" >> "$HEARTBEAT"
log "heartbeat written to $HEARTBEAT"

log "========== nightly build OK (changed=$CHANGED) =========="
exit 0