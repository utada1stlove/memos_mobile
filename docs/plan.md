# V1 Android Memos Wrapper Plan

## Summary

Build a small Tauri 2 Android shell around a self-hosted Memos site, keeping the Memos app untouched while enforcing a single configured origin and documenting all scope limits up front.

## Delivery Phases

### Phase 0

- Write `docs/plan.md`, `docs/scope.md`, and initialize `README.md`
- Record assumptions, constraints, and explicit non-goals
- Keep `docs/progess.md` as the progress tracker path

### Phase 1

- Scaffold a Tauri 2 + vanilla TypeScript project
- Read `MEMOS_BASE_URL` from centralized Rust config
- Create the main Android WebView window from Rust at runtime
- Restrict top-level navigation to the configured origin
- Handle Android back button through the native activity

### Phase 2

- Intercept off-origin links and open them in the system browser
- Attach an Android file chooser bridge for HTML file inputs
- Add a native retryable error overlay for network and SSL failures
- Add neutral V1 app metadata, launcher icon, and splash resources

### Phase 3

- Accept Android `ACTION_SEND` text and URLs
- Queue shared payloads on cold start and `onNewIntent`
- Attempt safe generic composer autofill through injected JavaScript
- Fall back to clipboard + toast when reliable insertion is not possible

### Phase 4

- Split debug and release env files
- Enforce HTTPS by default from Rust-side config validation
- Allow HTTP only in debug when `ALLOW_INSECURE_HTTP=1`
- Disable Android WebView debugging in release builds
- Block mixed content in the WebView

### Phase 5

- Add `scripts/doctor.sh`
- Add `scripts/build-android.sh`
- Make the build script initialize Android, sync overrides, patch cleartext policy, and run the requested build
- Document reproducible setup and build steps in `README.md`

## Implementation Decisions

- Keep `src-tauri/gen/android` generated, and commit only `src-tauri/android-overrides`
- Use Rust for config validation and the in-app origin allowlist
- Use Android native code for back button, external links, file chooser, error UI, and share intents
- Use a generic DOM insertion helper instead of rewriting any Memos UI

## Assumptions

- Package ID: `com.memos.mobile`
- Display name: `Memos Mobile`
- Android only
- Same-origin Memos auth only for V1
- Local build verification depends on installing the Android/Tauri toolchain first
