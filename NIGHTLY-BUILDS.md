# XKG Nightly Build Pipeline

This document describes the recurring build pipeline that keeps the public
XKG download links fresh so they never ship stale binaries.

## What runs and when

The pipeline is **two layers + a watchdog** for defense in depth:

| Layer | What | When (PDT) | When (UTC) | Where |
|---|---|---|---|---|
| 1. Cloud | GitHub Actions matrix (build + publish `nightly-YYYYMMDD` prerelease) | 19:00 | 02:00 | `.github/workflows/release.yml` |
| 2. Host  | Local `nightly-build.sh` (re-collects artifacts, regenerates checksums, bounces gate if anything changed) | 20:00 | 03:00 | `scripts/nightly-build.sh` via cron |
| 3. Watchdog | `healthcheck-nightly.sh` (every 30 min — writes `.last-build-failed` flag + optional Discord alert if no successful build in 26h) | every 30 min | every 30 min | `scripts/healthcheck-nightly.sh` via cron |

The 1-hour gap between layers 1 and 2 lets the cloud build land first; the
host script then either redoes the work locally (filling gaps if the cloud
failed) or confirms freshness and exits.

## Where to find logs

| File | What it contains |
|---|---|
| `/home/x2/xkg-releases/nightly-build.log` | Combined stdout+stderr of every `nightly-build.sh` run (cron `>>` append). One full run ≈ 6–10 seconds. |
| `/home/x2/xkg-releases/healthcheck.log`   | Every watchdog check (every 30 min, mostly one-line "healthy"). |
| `/home/x2/xkg-releases/gate.log`         | Output of the xkg-gate server (when restarted by the nightly script). |
| GitHub Actions UI                       | Cloud nightly runs (look for `schedule` trigger, e.g. `nightly-20260622` tag). |

Operational state files (created by the scripts):

| File | Meaning |
|---|---|
| `.last-build-success` | Heartbeat. First line is the UTC ISO timestamp of the last successful build. |
| `.last-build-failed`  | Written by the watchdog if `.last-build-success` is older than 26 hours. Cleared automatically once a fresh build lands. |
| `.nightly-build.lock` | flock(2) lock file. Prevents two `nightly-build.sh` from running at once. |
| `.checksums-before.sha256` / `.checksums-after.sha256` | Snapshots used to detect whether binaries actually changed between runs. |

## How to trigger a manual run

```bash
# Full run with gate restart (default; same as what cron runs)
bash /home/x2/xkg-releases/scripts/nightly-build.sh

# Skip the gate restart step (safe if you don't want to bounce the service)
bash /home/x2/xkg-releases/scripts/nightly-build.sh --skip-gate

# A different version tree (e.g. for a 0.2.0 staging dir)
VER=0.2.0 bash /home/x2/xkg-releases/scripts/nightly-build.sh --skip-gate

# Force-run the watchdog (e.g. when testing alerts)
MAX_AGE_HOURS=26 ALERT_COOLDOWN_MIN=0 bash /home/x2/xkg-releases/scripts/healthcheck-nightly.sh
```

You can also re-run the GitHub Actions nightly build on demand from the
Actions tab → "xkg-release" → "Run workflow".

## How to disable / enable

### Disable the host nightly build temporarily
```bash
crontab -e
# Comment out (prefix with #):
# 0 3 * * * /home/x2/xkg-releases/scripts/nightly-build.sh ...
```

### Disable the watchdog
```bash
crontab -e
# Comment out:
# */30 * * * * /home/x2/xkg-releases/scripts/healthcheck-nightly.sh ...
```

### Disable the cloud nightly
Edit `.github/workflows/release.yml` and remove (or comment) the
`schedule:` block under `on:`. The workflow will still trigger on tag
pushes and `workflow_dispatch`.

To re-enable, uncomment the lines and (for the cloud) push to the default
branch.

## Failure mode and alerting

1. **Build itself fails** (build.sh or verify-checksums.sh non-zero):
   - `nightly-build.sh` exits with a non-zero status (2 = build failed,
     3 = verify failed).
   - `nightly-build.log` records the full failure output.
   - `.last-build-success` is **not** updated, so the heartbeat stays
     stale.
   - The watchdog picks this up within 30 minutes.

2. **Watchdog detects staleness** (`.last-build-success` older than 26 h):
   - Writes `.last-build-failed` with the timestamp, host, age, and limit.
   - Sends a Discord alert (if `DISCORD_WEBHOOK` env var is set when the
     cron runs) — guarded by a 6-hour cooldown so we don't spam.
   - Exits 1 so any external monitor on the script's exit code can also
     alert.

3. **Gate restart fails** (the nightly build itself was OK, but killing
   the old gate / launching the new one broke):
   - `nightly-build.sh` exits 4.
   - `.last-build-success` is **still** written (the build itself was
     fine, only the service bounce failed).
   - **Important**: this means the watchdog will *not* alert on a gate
     restart failure — because the artifacts on disk are still fresh.
     That's intentional. To detect gate-restart failures separately,
     watch the script's exit code (e.g. from cron mail or a wrapper).

4. **False-positive alerts**:
   - If you intentionally skip a night (e.g. during maintenance), the
     watchdog will still trigger. Touch `.last-build-success` to silence
     it for another 26 hours:
     ```bash
     date -u '+%Y-%m-%dT%H:%M:%SZ' > /home/x2/xkg-releases/.last-build-success
     ```

5. **Recovery**:
   ```bash
   bash /home/x2/xkg-releases/scripts/nightly-build.sh        # retry
   cat /home/x2/xkg-releases/.last-build-failed              # what went wrong
   tail -100 /home/x2/xkg-releases/nightly-build.log         # last run details
   rm -f /home/x2/xkg-releases/.last-build-failed            # clear the flag once resolved
   ```

## Setting up Discord alerting (optional)

The watchdog supports an optional Discord webhook. To enable:

```bash
# 1. Get a webhook URL from your Discord server (Channel settings → Integrations → Webhooks)
# 2. Add to root's crontab env so cron can see it:
crontab -e
# At the top of the crontab (before any lines), add:
# DISCORD_WEBHOOK=https://discord.com/api/webhooks/XXXXXXXX/YYYYYYY

# Or, simpler — edit scripts/healthcheck-nightly.sh to default
# DISCORD_WEBHOOK to your URL.
```

The existing `/home/x2/.openclaw/workspace/scripts/discord-notify.sh` is
the notifier (curl wrapper, no extra deps).

## Files added or modified by this pipeline

| File | Status |
|---|---|
| `.github/workflows/release.yml` | **Modified** — added `on.schedule` block + additive `publish-nightly` job. Matrix and existing `publish` job untouched. |
| `scripts/nightly-build.sh`        | **New** |
| `scripts/healthcheck-nightly.sh`  | **New** |
| `scripts/build.sh`                | **Modified (bug fix)** — `sha256sum $files` → `find -print0 \| xargs -0 -r sha256sum` so filenames with spaces don't break checksum generation. |
| `scripts/verify-checksums.sh`     | **Modified (bug fix)** — skip empty checksums files (false positives from dirs that only contain subdirs) and propagate `sha256sum -c` exit codes out of the subshell so failures actually exit non-zero. |
| `NIGHTLY-BUILDS.md`               | **New** (this file) |

The matrix in `release.yml` is unchanged — only an `on.schedule` entry and
an additional `publish-nightly` job were added. The existing tag-push
behaviour is preserved.