# XKG Releases

Central, signed, checksummed release artifacts for every XKG app on every
supported platform. This directory is what the public downloads page
(workforge) and the local `xkg-gate` server serve from.

## Layout

```
v0.1.0/
├── desktop/
│   ├── linux/      # .deb, .AppImage, .rpm (x86_64)
│   ├── windows/    # NSIS .exe, WiX .msi (x64)
│   ├── macos/      # .dmg (aarch64 + x86_64)
│   └── checksums.sha256
├── mobile/
│   ├── android/    # .apk (release, signed), .aab
│   ├── ios/        # .ipa (unsigned; needs codesign)
│   └── checksums.sha256
├── web/
│   ├── linux/      # PyInstaller ELF binary
│   ├── windows/    # PyInstaller PE .exe
│   ├── docker/     # docker save tarball
│   └── checksums.sha256
└── RELEASE_NOTES.md
```

Every binary gets a SHA256 in the per-category `checksums.sha256`. The gate
serves `/releases/<canonical-filename>` and `/api/download/<file>` (with a
coupon token) straight out of this tree.

## How the pipeline works

1. **Builders** produce the raw installer in their native `target/.../bundle/`
   dir.
2. **`scripts/build.sh`** (or the GitHub Actions matrix) collects them into
   the per-platform per-app directory layout above.
3. **`scripts/rename-artifacts.sh`** normalizes filenames to the canonical
   `XKG-Desktop_0.1.0_amd64.deb` etc. form so the gate, downloads.html, and
   the website all agree.
4. **`sha256sum * > checksums.sha256`** is generated per directory.
5. **GitHub release** is published with the same artifacts (so the
   `releases/latest/download/...` URL on GitHub still works as a fallback).

The gate server (port 9095 on this host) has been updated to serve binaries
directly from this directory via `/releases/<file>` — no more 302 to the
template that GitHub ships.

## Reproducing a release locally

```bash
# 1. Build each app in its repo
cd /tmp/repos/xkg-desktop-clean/src-tauri && cargo tauri build
cd /tmp/repos/xkg-mobile-clean/mobile && flutter build apk --release
cd /tmp/repos/x-knowledge-graph/server && pyinstaller xkg-server.spec

# 2. Collect + rename
bash scripts/build.sh 0.1.0

# 3. Verify
bash scripts/verify-checksums.sh v0.1.0
```

## Verifying a download

```bash
# Pull the published checksum and compare
curl -fsS https://gate.seele.agency/releases/desktop/linux/checksums.sha256 \
  | grep XKG-Desktop_0.1.0_amd64.deb
sha256sum XKG-Desktop_0.1.0_amd64.deb
```

If you got the file from a GitHub release, the canonical SHA256 also lives
in the per-category `checksums.sha256` in the same release.

## Adding a new version

1. `mkdir -p vX.Y.Z/{desktop,mobile,web}`
2. Drop the signed installers into the right category subdirs.
3. Run `bash scripts/verify-checksums.sh vX.Y.Z` to regenerate `checksums.sha256`.
4. Bump the `FILE_PATHS` map in `/home/x2/xkg-gate/server.py` to point the
   new filenames at the new files.
5. Update `downloads.html` and `RELEASE_NOTES.md` accordingly.
6. Tag the repo: `git tag vX.Y.Z && git push --tags`.
