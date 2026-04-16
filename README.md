# Memos Mobile

Android-first Tauri 2 wrapper for a self-hosted Memos instance. The app loads one configured Memos origin inside a constrained mobile shell instead of rewriting the Memos frontend or backend.

## Current Status

- Phase 0 completed: docs, assumptions, boundaries, and baseline README are in place.
- Phase 1 implemented: centralized `MEMOS_BASE_URL` validation, remote window bootstrap, same-origin navigation guard, and Android back-button handling.
- Phase 2 implemented: external link handoff, Android file chooser support, native error overlay, and neutral V1 branding resources.
- Phase 3 implemented with a safe fallback: Android share intents queue text and URLs, try DOM autofill, then fall back to clipboard + toast if insertion is not reliable.
- Phase 4 implemented: debug/release env split, HTTPS-by-default validation, release-only rejection of HTTP, mixed-content blocking, and release-only WebView debugging disablement.
- Phase 5 implemented: `scripts/doctor.sh` and `scripts/build-android.sh` automate prerequisites checks, Android init, overrides sync, and build commands.
- Phase 6 implemented: GitHub Actions can build an `arm64` Android APK from this repository on every push to `main`.

An `arm64` release APK built from this code path has already been installed and smoke-tested locally on a physical Android device.

## Prerequisites

You need these before building:

- Node.js 20+
- npm 10+
- Rust + Cargo + `rustup`
- Android Studio / Android SDK
- `adb`
- Java 17+
- A POSIX shell on Windows such as Git Bash or WSL because the requested build scripts are `.sh`

Run the doctor script first:

```sh
./scripts/doctor.sh
```

## Configuration

All runtime configuration is compile-time embedded through environment files loaded by the build script.

- `.env.android.debug`: debug Android build settings
- `.env.android.release`: release Android build settings
- `.env.example`: documented template only

Supported variables:

- `MEMOS_BASE_URL`: required. Must be a full `https://` URL in release builds.
- `ALLOW_INSECURE_HTTP`: optional. Only `1` enables `http://` during debug builds. Release builds always reject it.

Examples:

```env
MEMOS_BASE_URL=https://memos.example.com
ALLOW_INSECURE_HTTP=0
```

```env
MEMOS_BASE_URL=http://10.0.2.2:5230
ALLOW_INSECURE_HTTP=1
```

## Build Flow

### 1. Install dependencies

```sh
npm install
```

### 2. Initialize the Android project once

```sh
npm run tauri android init
```

You can skip this manual step if you use `scripts/build-android.sh`, because the script initializes Android automatically when `src-tauri/gen/android` is missing.

### 3. Build a debug APK

```sh
./scripts/build-android.sh debug
```

### 4. Build a release APK

```sh
./scripts/build-android.sh release
```

### 5. Development loop

```sh
npm run tauri android dev
```

## Deploying a New APK via Git

The CI pipeline builds and signs an APK automatically on every push to `main`. The usual workflow is:

### Change your Memos server URL

Edit `.env.android.release`:

```env
MEMOS_BASE_URL=https://your-memos-server.example.com
```

Then push:

```sh
git add .env.android.release
git commit -m "Update Memos server URL"
git push origin main
```

### Change any other build parameter

| What to change | File |
|---|---|
| Memos server URL | `.env.android.release` |
| Allow HTTP in debug builds | `.env.android.debug` (`ALLOW_INSECURE_HTTP=1`) |
| Android API level / NDK / build-tools versions | `.github/workflows/android.yml` (`ANDROID_PLATFORM`, `ANDROID_NDK_VERSION`, `ANDROID_BUILD_TOOLS`) |
| Android permissions, share intent filter | `src-tauri/android-overrides/app/src/main/AndroidManifest.xml` |
| Back button, file chooser, share handling | `src-tauri/android-overrides/app/src/main/java/com/memos/mobile/MainActivity.kt` |
| App icons, colors, themes | `src-tauri/android-overrides/app/src/main/res/` |

After editing any of these files, commit and push to `main` to trigger a new build.

### Download the built APK

After CI finishes (≈7 minutes), go to the repository's **Actions** tab, click the latest run, and download the `memos-mobile-release` artifact. It contains the signed APK.

Or download directly with the GitHub CLI:

```sh
gh run download --repo utada1stlove/memos_mobile --dir ./artifacts
```

The APK will be at `artifacts/memos-mobile-release/app-universal-release-signed.apk`.

## GitHub Actions

This repository includes a workflow at `.github/workflows/android.yml`.

- Every push to `main` triggers an Android release build.
- The workflow uploads the signed APK as a GitHub Actions artifact named `memos-mobile-release`.

### Signing behavior

The workflow supports two signing modes:

- Preferred: configure repository secrets so every build uses the same keystore and the APK can be upgraded in place.
- Fallback: if no signing secrets are configured, CI generates a temporary test keystore and still uploads an installable APK artifact.

For stable release signatures, add these repository secrets:

- `ANDROID_KEYSTORE_BASE64`: base64-encoded keystore file contents
- `ANDROID_KEYSTORE_PASSWORD`: keystore password
- `ANDROID_KEY_ALIAS`: alias name inside the keystore
- `ANDROID_KEY_PASSWORD`: key password

If you skip these secrets, the workflow still succeeds, but APK signatures can change between runs.

## Project Layout

- `src-tauri/src`: Rust bootstrap, config validation, remote WebView creation, and the allowlist guard
- `src-tauri/android-overrides`: checked-in Android customizations that are copied into generated `src-tauri/gen/android`
- `docs`: plan, scope, and progress tracker
- `scripts`: doctor/build automation

`src-tauri/gen/android` is intentionally generated at build/init time. The repo keeps only the overrides we own.

## Android Behavior

### Navigation and security

- Only the configured Memos origin is allowed in-app.
- Off-origin top-level navigations are opened in the system browser by Android native code.
- Mixed content is disabled in the Android WebView.
- Release builds reject non-HTTPS `MEMOS_BASE_URL`.

### Session persistence

The app uses the default persistent Android WebView data store. No incognito or ephemeral session mode is enabled.

### File uploads

The Android shell installs a custom `WebChromeClient` chooser bridge so standard HTML file inputs can use the system picker.

### Share intent behavior

- `ACTION_SEND` with `text/plain` is supported.
- Shared URLs are handled through the same text pipeline.
- The app tries to insert the payload into a visible `textarea`, `contenteditable`, `role="textbox"`, or text input on the loaded Memos page.
- If no safe insertion target is found, the payload is copied to clipboard and the user gets a toast fallback notice.

## Known Limits

- Same-origin authentication is the supported V1 path. External OAuth or SSO flows that require arbitrary in-app browsing are out of scope.
- Share autofill is intentionally generic because Memos DOM structure may vary by version.
- Binary attachment share intents are not included in V1.
- GitHub Actions builds produce a `universal` APK (all ABIs in one package) rather than a per-ABI split.
