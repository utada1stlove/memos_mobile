# V1 Scope

## In Scope

- Android-only app shell
- Tauri 2 project scaffold
- Centralized `MEMOS_BASE_URL` configuration
- One allowed in-app origin
- Session persistence across app restarts through the persistent WebView store
- Android back-button support
- HTML file upload support
- External browser handoff for off-origin top-level links
- Basic network and SSL error handling
- Android text and URL share intent support with a documented fallback
- Neutral V1 icon, splash, and metadata

## Out of Scope

- Rewriting the Memos frontend
- Rewriting the Memos backend
- iOS support
- Offline sync
- Push notifications
- Native editor screens
- Multi-account support
- Arbitrary in-app browsing outside the configured domain
- Binary attachment share intents
- External OAuth or SSO flows that require broader in-app navigation

## Security Constraints

- `https://` only by default
- Debug HTTP allowed only through `ALLOW_INSECURE_HTTP=1`
- Release builds always reject HTTP
- Mixed content disabled in Android WebView
- WebView debugging disabled in release builds
- Off-origin top-level navigation never stays inside the app

## Share Intent Policy

- Accept `ACTION_SEND` with `text/plain`
- Treat plain text and URLs as one normalized payload type
- Try generic DOM insertion into the loaded Memos page
- If no reliable target is available, copy the payload to clipboard and show a clear handoff toast

## Generated vs Owned Files

- Owned in repo: docs, Rust source, frontend source, scripts, and `src-tauri/android-overrides`
- Generated at init/build time: `src-tauri/gen/android`
