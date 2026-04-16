# Progress

Last updated: 2026-04-16

Implementation is in place across Phases 0-6. Local physical-device installation has been smoke-tested. GitHub Actions automation has been added to this repository, but the first remote workflow run is still pending verification.

## Phase 0
- [x] plan.md created
- [x] scope.md created
- [x] README initialized

## Phase 1
- [x] Tauri Android project scaffolded
- [x] MEMOS_BASE_URL config added
- [x] Allowed-domain navigation guard added
- [ ] Session persistence verified on device/emulator
- [x] Back button behavior implemented

## Phase 2
- [x] External browser handling added
- [ ] File upload verified on device/emulator
- [x] Error states added
- [x] UI polish completed

## Phase 3
- [x] Android share intent receives text
- [x] Android share intent receives URLs
- [x] Memo creation handoff implemented or fallback documented

## Phase 4
- [x] Debug/release config separated
- [x] WebView debug disabled in release
- [x] HTTPS-only restriction enforced
- [x] Domain allowlist finalized

## Phase 5
- [x] doctor.sh added
- [x] build-android.sh added
- [x] Debug build documented
- [x] Release build documented

## Phase 6
- [x] `memos_mobile` repository prepared from the working local project
- [x] GitHub Actions workflow added for `arm64` Android builds
- [x] CI signing flow added with secret-based signing and temporary-key fallback
- [ ] First GitHub-hosted workflow run verified on GitHub

## Notes

- Android generated sources are not committed directly. The repo keeps `src-tauri/android-overrides`, and `scripts/build-android.sh` syncs them into `src-tauri/gen/android` after `tauri android init`.
- HTTP support remains debug-only and still requires `ALLOW_INSECURE_HTTP=1`.
- The share flow uses generic DOM insertion and falls back to clipboard + toast when Memos UI structure does not expose a safe editable target.
- A local `arm64` release APK built from this code path has already been installed successfully on a real Android device.
