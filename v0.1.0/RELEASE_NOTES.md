# XKG v0.1.0 — Honest "What Ships" Notes

**Released:** 2026-06-21
**Tag:** `v0.1.0`
**Pipeline:** first end-to-end cut — real binaries, real checksums, real
download path via `gate.seele.agency` → `/releases/<file>`.

This is a real, runnable release. It is **not** a feature-complete v1.0.
We're publishing it now so the public download links stop shipping the
Tauri+React template that GitHub renders when the release is empty.

## What's actually in v0.1.0

### 🖥 xkg-desktop (Tauri + React) — v0.1.0
- **Linux** (x86_64): `.deb` (4.4 MB), `.AppImage` (80 MB), `.rpm` (4.4 MB)
  — built and signed. Real installer, real content.
- **Windows** (x64): NSIS `.exe` (5.4 MB). Real installer.
- **macOS**: DMG placeholder in the gate — not yet built in this cut.
  We are publishing the **download slot** so the path works; the gate
  will return 404 until the macOS runner is wired up. Do not advertise
  the macOS button as live in marketing copy until TASK-XKG-20260621-134
  ships a real DMG.

### 📱 xkg-mobile (Flutter) — v0.1.0
- **Android**: signed release APK (22.4 MB) at
  `xkg-mobile-0.1.0-release.apk` and the legacy `app-release.apk` slot.
  Real Flutter build with the full Hive-backed lib/, real `pubspec.yaml`
  dependencies (http, hive, hive_flutter, url_launcher, shared_preferences).
- **iOS**: not built in this cut (no macOS runner in the matrix yet).
  Same deal as macOS desktop: the slot exists, the gate 404s until we wire
  the runner.

### 🌐 x-knowledge-graph web (Flask + PyInstaller) — v0.5.4
- Linux ELF (PyInstaller), Windows PE, and Docker `save` tarball are
  declared in the gate but **not yet built** in this cut. The pipeline
  scripts are in place; the TASK-XKG-20260621-133 build is still in
  progress. Files will land here as soon as that task lands.

## What's NOT in v0.1.0 (be honest with users)

- ❌ **macOS desktop DMG** — pipeline defined, file absent. Gate returns 404.
- ❌ **iOS IPA** — same.
- ❌ **Web (PyInstaller / Docker)** — TASK-133 is still building.
- ❌ **Code signing on Windows / macOS** — the executables are unsigned.
  Windows will SmartScreen-warn; macOS will Gatekeeper-block. Use
  "More info → Open" for now, or sign before shipping to non-technical
  users.
- ❌ **Auto-update** — every release is a fresh download.
- ❌ **Multi-LLM grid UI polish** — backend wired in
  `xkg-mobile/lib/services/llm_app.dart` (Grok/ChatGPT/Claude/Gemini/
  Perplexity all stubbed), but the live screen is still MVP. Don't claim
  "production LLM orchestration" in marketing.
- ❌ **Seele / griptoad cloud sync** — local-only with Hive. Sync protocol
  exists in `xkg_service.dart` but is not pointed at a live server.

## SHA256 (top files)

```
85b57c91600bb47439640eebde6a1521658cdfb3918687f24cf437da31c088ca  XKG-Desktop_0.1.0_amd64.deb
1d4775fd398cc23b9d97f21a67848cb9e98687a4bc6bbc8661b3d873a6bf191d  XKG-Desktop_0.1.0_amd64.AppImage
afef3fc025139230eb7d9ca0b88ed8d9a768cc68d26cc2a8938c4e48f798ca9b  XKG-Desktop-0.1.0-1.x86_64.rpm
d626b5768ff0fafdcd93cb7a11c8ae279a0b4df1d2b555302bd90390deea092b  XKG-Desktop_0.1.0_x64-setup.exe
3e099f958bc894b32eb49a6012b91b0668689e9c5426b638870b4b3885d85a9d  xkg-mobile-0.1.0-release.apk
```

Full checksums in each category's `checksums.sha256` file.

## Verifying

```bash
# Every binary
( cd desktop/linux && sha256sum -c checksums.sha256 )
( cd desktop/windows && sha256sum -c checksums.sha256 )
( cd mobile/android && sha256sum -c checksums.sha256 )
```

## Build provenance

| File | Built by | Host | Source commit |
|---|---|---|---|
| desktop/* | Tauri 1.5 + Node 20 + Rust 1.75 | x2-nuc (Linux) + windows-2022 runner | `xkg-desktop-clean@0.1.0` |
| mobile/android/* | Flutter 3.24.0 + Android SDK 34 | x2-nuc (Linux) | `xkg-mobile-clean@0.1.0` |
| web/* (pending) | PyInstaller 6.x + Docker 24 | TASK-133 in progress | `x-knowledge-graph@0.5.4` |
