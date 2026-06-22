#!/usr/bin/env bash
# scripts/rename-artifacts.sh
# Renames raw builder output to the canonical public filenames the
# gate server (/releases/<file>) and downloads.html use. Also drops
# any debug/profile artifacts.
#
# Run from the dist/ directory after `actions/download-artifact@v4`
# has pulled every matrix shard into per-shard subdirs.
set -euo pipefail

shopt -s nullglob

# Layout we expect after download-artifact:
#   dist/
#     desktop-ubuntu-22.04/  desktop-windows-2022/  desktop-macos-14/
#     mobile-ubuntu-22.04/   mobile-macos-14/
#     web-ubuntu-22.04/      web-windows-2022/
# Each subdir contains the raw bundle output for that platform.

log() { echo "[rename] $*" >&2; }

move_to() {
  local src="$1" cat="$2" name="$3"
  mkdir -p "$cat"
  mv -f "$src" "$cat/$name"
  log "$cat/$name <- $src"
}

# ── desktop / linux (.deb, .AppImage, .rpm) ──
for f in dist/desktop-ubuntu-22.04/src-tauri/target/release/bundle/deb/*_amd64.deb; do
  base=$(basename "$f" | sed -E 's/^xkg[-_]?desktop[_-]/XKG-Desktop_/I')
  move_to "$f" "desktop/linux" "$base"
done
for f in dist/desktop-ubuntu-22.04/src-tauri/target/release/bundle/appimage/*_amd64.AppImage; do
  base=$(basename "$f" | sed -E 's/^xkg[-_]?desktop[_-]/XKG-Desktop_/I')
  move_to "$f" "desktop/linux" "$base"
done
for f in dist/desktop-ubuntu-22.04/src-tauri/target/release/bundle/rpm/*.x86_64.rpm; do
  base=$(basename "$f" | sed -E 's/^xkg[-_]?desktop[_-]?/XKG-Desktop-/I; s/\.x86_64$/-1.x86_64/')
  move_to "$f" "desktop/linux" "$base"
done

# ── desktop / windows (.exe NSIS, .msi WiX) ──
for f in dist/desktop-windows-2022/src-tauri/target/x86_64-pc-windows-msvc/release/bundle/nsis/*_x64-setup.exe; do
  base=$(basename "$f" | sed -E 's/^xkg[-_]?desktop[_-]/XKG-Desktop_/I')
  move_to "$f" "desktop/windows" "$base"
done
for f in dist/desktop-windows-2022/src-tauri/target/x86_64-pc-windows-msvc/release/bundle/msi/*_x64_en-US.msi; do
  base=$(basename "$f" | sed -E 's/^xkg[-_]?desktop[_-]/XKG-Desktop_/I')
  move_to "$f" "desktop/windows" "$base"
done

# ── desktop / macos (DMG for aarch64 + x86_64) ──
for arch in aarch64 x86_64; do
  for f in dist/desktop-macos-14/src-tauri/target/${arch}-apple-darwin/release/bundle/dmg/*_${arch}.dmg; do
    base=$(basename "$f" | sed -E 's/^xkg[-_]?desktop[_-]/XKG-Desktop_/I')
    move_to "$f" "desktop/macos" "$base"
  done
done

# ── mobile / android (.apk, .aab) ──
for f in dist/mobile-ubuntu-22.04/mobile/build/app/outputs/flutter-apk/app-release.apk; do
  move_to "$f" "mobile/android" "xkg-mobile-0.1.0-release.apk"
done
for f in dist/mobile-ubuntu-22.04/mobile/build/app/outputs/flutter-apk/app-release.apk; do
  cp -f "$f" "mobile/android/app-release.apk"  # legacy name used by gate
done
for f in dist/mobile-ubuntu-22.04/mobile/build/app/outputs/bundle/release/app-release.aab; do
  move_to "$f" "mobile/android" "xkg-mobile-0.1.0-release.aab"
done

# ── mobile / ios (.ipa, unsigned in CI) ──
for f in dist/mobile-macos-14/mobile/build/ios/ipa/*.ipa; do
  base=$(basename "$f" | sed -E 's/^Runner/ipa/; s/^xkg[-_]?mobile[_-]?/xkg-mobile-/I')
  move_to "$f" "mobile/ios" "xkg-mobile-0.1.0.ipa"
done

# ── web / linux (PyInstaller ELF) ──
for f in dist/web-ubuntu-22.04/server/dist/xkg-server; do
  if [ -f "$f" ]; then
    move_to "$f" "web/linux" "xkg-server_0.5.4_amd64"
    chmod +x "web/linux/xkg-server_0.5.4_amd64"
  fi
done

# ── web / windows (PyInstaller PE) ──
for f in dist/web-windows-2022/server/dist/xkg-server.exe; do
  if [ -f "$f" ]; then
    move_to "$f" "web/windows" "xkg-server_0.5.4_x64.exe"
  fi
done

# ── web / docker (image tar) ──
for f in dist/web-ubuntu-22.04/server/xkg-server-*.tar; do
  if [ -f "$f" ]; then
    base=$(basename "$f" | sed -E 's/^xkg-server-v/xkg-server-/; s/^xkg-server-/xkg-server-/')
    move_to "$f" "web/docker" "xkg-server-0.5.4.tar"
  fi
done

# Remove the per-shard dirs we no longer need
rm -rf dist/desktop-* dist/mobile-* dist/web-*

# Drop debug/profile bundles if they slipped through
find . -type f \( -name "*.debug" -o -name "*-debug.apk" -o -name "*-profile.apk" -o -name "*-unsigned.apk" \) -delete

log "rename done. Final tree:"
find . -type f | sort
