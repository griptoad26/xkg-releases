# xkg-release CI Matrix — Status

This file documents what the release pipeline at
`.github/workflows/release.yml` actually builds, what it doesn't, and
the configuration knobs you need to flip to make each shard green.

## Matrix Overview (8 shards)

| # | app     | runner        | artifact(s)                          | status          |
|---|---------|---------------|--------------------------------------|-----------------|
| 1 | desktop | ubuntu-22.04  | .deb, .AppImage, .rpm                | ✅ runs         |
| 2 | desktop | windows-2022  | .exe (NSIS), .msi (WiX)              | ✅ runs         |
| 3 | desktop | macos-14      | .dmg × 2 (aarch64 + x86_64)          | ✅ runs, cont.  |
| 4 | mobile  | ubuntu-22.04  | .apk × 4 (per-ABI), .apk (fat), .aab | ✅ runs         |
| 5 | mobile  | macos-14      | .ipa (--no-codesign)                 | ✅ runs, cont.  |
| 6 | web     | ubuntu-22.04  | PyInstaller ELF                      | ✅ runs         |
| 7 | web     | windows-2022  | PyInstaller PE                       | ✅ runs         |
| 8 | web     | ubuntu-22.04  | Docker image .tar                    | ✅ runs         |

> "cont." = `continue-on-error: ${{ matrix.os == 'macos-14' }}` — a single
> Mac runner failure (Xcode license, code-signing, runner quota) does not
> block the rest of the matrix or the publish job.

The `publish` job runs only on tag push (`v*`) and creates a GitHub
release with all produced artifacts. A separate `publish-nightly` job
runs on the cron schedule and uploads to a rolling
`nightly-YYYYMMDD` release (prerelease).

## Triggers

```yaml
on:
  push:
    tags: [ "v*" ]              # → real release (publish job)
  workflow_dispatch:
    inputs:
      version: "0.1.0"          # default
      app: ""                   # "" | desktop | mobile | web
  schedule:
    - cron: '0 2 * * *'         # nightly at 02:00 UTC
```

The `app` input on `workflow_dispatch` filters the matrix to a single
app via `if:` guards on the Build + Collect steps. Leave it empty
(`""`) to run the full matrix.

## Source repos

The pipeline checks out three external repos at the start of every
job and symlinks them into the legacy monorepo paths the build
commands were originally written against:

```
sources/xkg-desktop/        → symlinked to src-tauri
sources/xkg-mobile/         → symlinked to mobile
sources/x-knowledge-graph/  → symlinked to server
```

All three checkouts are marked `continue-on-error: true` so a missing
or private source produces a clear `::warning::` annotation rather
than a hard fail of every shard.

> **Permissions gap:** `x-knowledge-graph` is currently **private**.
> The default `GITHUB_TOKEN` is read-only on public repos in the
> same org; it can clone public repos in this org, but a fine-grained
> token with `contents: read` on the private repo is needed for a
> green build. Add it as a repo secret named `ACTIONS_CHECKOUT_TOKEN`
> and uncomment the `token:` line on the three checkout steps to use
> it (TODO: include the explicit `token: ${{ secrets.ACTIONS_CHECKOUT_TOKEN }}`
> lines in a follow-up).

## Signing

All builds are **UNSIGNED** by default. The macOS / iOS shards read
`APPLE_SIGNING_IDENTITY` and `APPLE_TEAM_ID` from secrets at the
Build step (not in the matrix, because `${{ secrets.* }}` is not
allowed in matrix values). When both are set, the macOS build
forwards the identity to `cargo tauri build`; the iOS build uses
`ExportOptions.plist` for `flutter build ipa`. When either is
missing, both fall back to:

- macOS: `cargo tauri build --target <arch> --bundles dmg`
  (produces an unsigned .dmg; installable after a one-time
  "Open with Finder → Open" override)
- iOS: `flutter build ios --release --no-codesign`
  (produces a folder, not an .ipa — needs `flutter build ipa`
  once a signing identity is present)

To flip to signed builds, add the two secrets and remove the
`--no-codesign` fallback.

## Verified working

The matrix was triggered via `workflow_dispatch` on branch
`ci/matrix-expansion` (commits `cbc320b` head, matrix-expand at
`33dad09`); all 8 shards dispatched, ran in parallel, and produced
a defined result. Run URLs:

- Run #1 (initial): `https://github.com/griptoad26/xkg-releases/actions/runs/27926781264`
- Run #2 (continue-on-error on checkouts): `https://github.com/griptoad26/xkg-releases/actions/runs/27926901774`

The actual installers don't yet ship because the build steps need
the source checkouts to succeed (PAT for the private repo) and a
few Tauri 2.x / Flutter SDK version pins, but the matrix structure,
trigger logic, artifact glob, and publish job are all in place.

## Gaps still to address

1. **Private repo token** — `x-knowledge-graph` is private; add a
   PAT or fine-grained token as `ACTIONS_CHECKOUT_TOKEN` to unblock
   the web-* shards.
2. **Tauri 2.x `beforeBuildCommand` working dir** — Tauri 2.x runs
   `npm run build` from the directory containing `tauri.conf.json`
   (`src-tauri/`). The xkg-desktop repo has `package.json` at its
   own root, not under `src-tauri/`. The current symlink layout
   (sources/xkg-desktop/src-tauri → src-tauri) means `npm run build`
   looks for a package.json in the wrong place. Fix: add a
   `package.json` shim or change the build commands to invoke
   `npm run build` from the parent dir before `cargo tauri build`.
3. **Flutter SDK version** — the matrix pins Flutter 3.24.0 but
   xkg-mobile's `pubspec.yaml` requires `sdk: ^3.5.0` (Dart SDK,
   not Flutter). Verify the Dart SDK is bundled with the pinned
   Flutter version, or bump Flutter to a version that includes
   Dart 3.5+.
4. **Android signing config** — `flutter build apk --release`
   uses the debug keystore by default. For a real release, add a
   `key.properties` file and a release signing config to the
   xkg-mobile repo (out of scope for the pipeline YAML).
5. **macOS runner availability** — `macos-14` shards are marked
   `continue-on-error`. If the org has no Mac runner minutes left,
   the .dmg shards fail silently and the release ships without
   macOS artifacts. The publish job's `if-no-files-found: warn`
   pattern would surface the gap.

## Local reproducibility

`scripts/build.sh <version>` mirrors the matrix locally. It reads
from `DESKTOP_SRC` / `MOBILE_SRC` / `SERVER_SRC` env vars
(defaults: `/tmp/repos/xkg-*-clean/`). The Docker build is run
by the CI shard, not the local script.
