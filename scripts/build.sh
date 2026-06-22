#!/usr/bin/env bash
# scripts/build.sh <version>
#
# Local-release builder. Mirrors what the GitHub Actions matrix does,
# so a maintainer with the source repos on this machine can produce a
# full vX.Y.Z tree in one command.
#
# Usage:  bash scripts/build.sh 0.1.0
set -euo pipefail

VER="${1:-0.1.0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/v$VER"
DESKTOP_SRC="${DESKTOP_SRC:-/tmp/repos/xkg-desktop-clean/src-tauri}"
MOBILE_SRC="${MOBILE_SRC:-/tmp/repos/xkg-mobile-clean/mobile}"
SERVER_SRC="${SERVER_SRC:-/tmp/repos/x-knowledge-graph/server}"

log() { echo "[build] $*" >&2; }

mkdir -p "$OUT"/{desktop/{linux,windows,macos},mobile/{android,ios},web/{linux,windows,docker}}

# ── desktop / linux ──
if [ -d "$DESKTOP_SRC" ]; then
  log "collecting desktop/linux from $DESKTOP_SRC"
  for f in "$DESKTOP_SRC/target/release/bundle/deb/"*.deb; do
    [ -f "$f" ] || continue
    name=$(basename "$f" | sed -E 's/^xkg[-_]?desktop[_-]/XKG-Desktop_/I')
    cp -f "$f" "$OUT/desktop/linux/$name"
  done
  for f in "$DESKTOP_SRC/target/release/bundle/appimage/"*.AppImage; do
    [ -f "$f" ] || continue
    name=$(basename "$f" | sed -E 's/^xkg[-_]?desktop[_-]/XKG-Desktop_/I')
    cp -f "$f" "$OUT/desktop/linux/$name"
  done
  for f in "$DESKTOP_SRC/target/release/bundle/rpm/"*.rpm; do
    [ -f "$f" ] || continue
    name=$(basename "$f" | sed -E 's/^xkg[-_]?desktop[_-]?/XKG-Desktop-/I; s/\.x86_64$/-1.x86_64/')
    cp -f "$f" "$OUT/desktop/linux/$name"
  done
else
  log "skipping desktop: $DESKTOP_SRC not present"
fi

# ── desktop / windows ──
if [ -d "$DESKTOP_SRC/target/x86_64-pc-windows-msvc/release/bundle" ]; then
  log "collecting desktop/windows"
  for f in "$DESKTOP_SRC/target/x86_64-pc-windows-msvc/release/bundle/nsis/"*.exe; do
    [ -f "$f" ] || continue
    name=$(basename "$f" | sed -E 's/^xkg[-_]?desktop[_-]/XKG-Desktop_/I')
    cp -f "$f" "$OUT/desktop/windows/$name"
  done
  for f in "$DESKTOP_SRC/target/x86_64-pc-windows-msvc/release/bundle/msi/"*.msi; do
    [ -f "$f" ] || continue
    name=$(basename "$f" | sed -E 's/^xkg[-_]?desktop[_-]/XKG-Desktop_/I')
    cp -f "$f" "$OUT/desktop/windows/$name"
  done
fi
# cross-compiled on linux
if [ -d "$DESKTOP_SRC/target/x86_64-pc-windows-gnu/release/bundle" ]; then
  for f in "$DESKTOP_SRC/target/x86_64-pc-windows-gnu/release/bundle/nsis/"*.exe; do
    [ -f "$f" ] || continue
    name=$(basename "$f" | sed -E 's/^xkg[-_]?desktop[_-]/XKG-Desktop_/I')
    cp -f "$f" "$OUT/desktop/windows/$name"
  done
fi

# ── desktop / macos (only present on a real mac runner) ──
for arch in aarch64 x86_64; do
  for f in "$DESKTOP_SRC/target/${arch}-apple-darwin/release/bundle/dmg/"*.dmg; do
    [ -f "$f" ] || continue
    name=$(basename "$f" | sed -E 's/^xkg[-_]?desktop[_-]/XKG-Desktop_/I')
    cp -f "$f" "$OUT/desktop/macos/$name"
  done
done

# ── mobile / android ──
if [ -d "$MOBILE_SRC" ]; then
  log "collecting mobile/android from $MOBILE_SRC"
  if [ -f "$MOBILE_SRC/build/app/outputs/flutter-apk/app-release.apk" ]; then
    cp -f "$MOBILE_SRC/build/app/outputs/flutter-apk/app-release.apk" \
          "$OUT/mobile/android/xkg-mobile-0.1.0-release.apk"
    cp -f "$MOBILE_SRC/build/app/outputs/flutter-apk/app-release.apk" \
          "$OUT/mobile/android/app-release.apk"
  fi
  if [ -f "$MOBILE_SRC/build/app/outputs/bundle/release/app-release.aab" ]; then
    cp -f "$MOBILE_SRC/build/app/outputs/bundle/release/app-release.aab" \
          "$OUT/mobile/android/xkg-mobile-0.1.0-release.aab"
  fi
fi

# ── mobile / ios (only on mac) ──
if [ -d "$MOBILE_SRC/build/ios/ipa" ]; then
  cp -f "$MOBILE_SRC/build/ios/ipa/"*.ipa "$OUT/mobile/ios/xkg-mobile-0.1.0.ipa" 2>/dev/null || true
fi

# ── web ──
if [ -d "$SERVER_SRC" ]; then
  log "collecting web from $SERVER_SRC"
  [ -f "$SERVER_SRC/dist/xkg-server" ]      && cp -f "$SERVER_SRC/dist/xkg-server"      "$OUT/web/linux/xkg-server_0.5.4_amd64"
  [ -f "$SERVER_SRC/dist/xkg-server.exe" ]  && cp -f "$SERVER_SRC/dist/xkg-server.exe"  "$OUT/web/windows/xkg-server_0.5.4_x64.exe"
  for tar in "$SERVER_SRC"/xkg-server-*.tar; do
    [ -f "$tar" ] || continue
    cp -f "$tar" "$OUT/web/docker/xkg-server-0.5.4.tar"
  done
fi

# ── checksums ──
log "generating checksums"
find "$OUT" -type d | while read -r d; do
  # Collect filenames (may contain spaces — unquoted $files would break
  # word splitting). Use find -print0 + xargs -0 to preserve them safely.
  find "$d" -maxdepth 1 -type f ! -name "checksums.sha256" -print0 \
    | xargs -0 -r sha256sum > "$d/checksums.sha256" 2>/dev/null || true
done

# master list
( cd "$OUT" && find . -type f ! -name "checksums.sha256" -exec sha256sum {} \; | sort > ALL_CHECKSUMS.sha256 )

log "done. Tree:"
( cd "$OUT" && find . -maxdepth 3 -type f | sort )
