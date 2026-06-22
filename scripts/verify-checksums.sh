#!/usr/bin/env bash
# scripts/verify-checksums.sh <version>
#
# Re-verifies every published binary in v<version>/ against the saved
# checksums.sha256 files. Exits non-zero on any mismatch.
set -euo pipefail

VER="${1:-0.1.0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/v$VER"

if [ ! -d "$OUT" ]; then
  echo "No such release: $OUT" >&2
  exit 1
fi

errors=0
while read -r sf; do
  dir=$(dirname "$sf")
  # Skip empty checksums files (directories that hold only subdirectories,
  # e.g. mobile/ios, desktop/macos — there's nothing to verify at this level).
  if [ ! -s "$sf" ]; then
    echo "[verify] $dir (empty, skipping)"
    continue
  fi
  echo "[verify] $dir"
  # Run sha256sum -c without `set -e` masking: capture exit code directly.
  ( cd "$dir" && sha256sum -c checksums.sha256 --strict ) || errors=$((errors+1))
done < <(find "$OUT" -name "checksums.sha256" -type f)

if [ $errors -gt 0 ]; then
  echo "[verify] FAILED: $errors category/ies with mismatches" >&2
  exit 1
fi
echo "[verify] all checksums match ✓"
