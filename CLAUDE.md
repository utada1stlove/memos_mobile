# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Memos Mobile is an Android-first Tauri 2 wrapper for a self-hosted [Memos](https://usememos.com/) instance. It does **not** rewrite the Memos frontend — it loads one configured Memos origin inside a constrained Android WebView shell.

## Commands

### Prerequisites check
```bash
./scripts/doctor.sh
```

### Local development (desktop preview)
```bash
npm run dev          # Start Vite dev server
npm run tauri dev    # Run Tauri desktop app with HMR
```

### Android builds
```bash
# First-time setup (generates src-tauri/gen/android/)
npm run tauri android init

# Debug build
./scripts/build-android.sh debug

# Release build (arm64 APK)
./scripts/build-android.sh release --target aarch64 --apk

# Sign the APK
./scripts/sign-android.sh <unsigned-apk-path> <signed-apk-path>
```

### TypeScript checks
```bash
npm run build    # tsc (no-emit) + vite build
```

No automated test suite exists — the app is smoke-tested on a physical Android device.

## Architecture

### Key design principle
The Rust layer is the heart of the app. The TypeScript frontend (`src/`) is intentionally minimal — it only renders an error fallback page if Rust fails to open the remote WebView.

### Data flow
1. `AppConfig::load()` (`src-tauri/src/config.rs`) reads `MEMOS_BASE_URL` and `ALLOW_INSECURE_HTTP` from compile-time env vars (via `option_env!`), validates URL + security policy.
2. `lib.rs` (`#[tauri::mobile_entry_point]`) either creates a remote WebView pointing at the Memos origin, or an error window.
3. The remote WebView injects a JS script that sets up `window.__MEMOS_MOBILE__` (share intent payload delivery, `retryCurrentPage`) and enforces the `on_navigation` origin guard.
4. If something goes wrong, `window.__MEMOS_BOOTSTRAP_ERROR__` is set via the injected script and `src/main.ts` updates the fallback UI.

### Android customizations (`src-tauri/android-overrides/`)
These files are **checked in** and synced into the generated `src-tauri/gen/android/` by `build-android.sh` on every build. Never edit `src-tauri/gen/android/` directly — edit the overrides instead:
- `AndroidManifest.xml` — share intent filter, permissions
- `java/com/memos/mobile/MainActivity.kt` — back-button handling, file chooser bridge, share intent handling, error overlay
- `res/` — launcher icons, splash background, light/dark themes

### Build script responsibilities (`scripts/build-android.sh`)
Beyond calling `tauri android build`, the script:
- Syncs `android-overrides/` → `src-tauri/gen/android/`
- Patches `build.gradle.kts`: `usesCleartextTraffic` and splashscreen dependency

### Environment configuration
Copy `.env.example` to `.env.android.debug` and `.env.android.release`. Both files require `MEMOS_BASE_URL`. Release builds reject `http://` URLs unconditionally (enforced in both `config.rs` and `build-android.sh`).

### CI/CD (`.github/workflows/android.yml`)
Builds a signed arm64 release APK on every push to `main`. Signing uses `ANDROID_KEYSTORE_BASE64` secret if present; falls back to a temporary generated keystore. Artifact is retained for 14 days.

Optional signing secrets: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`.

## Important constraints
- `src-tauri/gen/android/` is in `.gitignore` — it's regenerated from `android-overrides/` at build time.
- CSP is intentionally `null` in `tauri.conf.json` — the content is the self-hosted Memos site.
- The `tauri.conf.json` `create: false` setting means the window is created dynamically in Rust, not by the framework.
- Rust crate type must include `staticlib`, `cdylib`, `rlib` — required for Android cross-compilation.
