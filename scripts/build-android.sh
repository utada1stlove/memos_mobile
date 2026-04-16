#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
MODE=${1:-debug}
if [ $# -gt 0 ]; then
  shift
fi

usage() {
  cat <<'EOF'
Usage:
  ./scripts/build-android.sh [debug|release] [tauri-android-build-args...]
EOF
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$1" >&2
    exit 1
  fi
}

sync_dir() {
  SRC=$1
  DEST=$2
  mkdir -p "$DEST"
  cp -R "$SRC"/. "$DEST"/
}

patch_cleartext_setting() {
  BUILD_FILE=$1
  VALUE=$2
  TMP_FILE=$BUILD_FILE.tmp

  awk -v value="$VALUE" '
    {
      gsub(/manifestPlaceholders\["usesCleartextTraffic"\][[:space:]]*=[[:space:]]*".*"/, "manifestPlaceholders[\"usesCleartextTraffic\"] = \"" value "\"");
      print
    }
  ' "$BUILD_FILE" > "$TMP_FILE"
  mv "$TMP_FILE" "$BUILD_FILE"
}

ensure_splashscreen_dependency() {
  BUILD_FILE=$1
  TMP_FILE=$BUILD_FILE.tmp

  if grep -q 'androidx.core:core-splashscreen' "$BUILD_FILE"; then
    return
  fi

  awk '
    /dependencies[[:space:]]*\{/ && !injected {
      print
      print "    implementation(\"androidx.core:core-splashscreen:1.0.1\")"
      injected=1
      next
    }
    {
      print
    }
  ' "$BUILD_FILE" > "$TMP_FILE"
  mv "$TMP_FILE" "$BUILD_FILE"
}

case "$MODE" in
  debug|release) ;;
  *)
    usage
    exit 1
    ;;
esac

require_command npm
require_command cargo
require_command rustup
require_command java

if [ -z "${ANDROID_HOME:-}" ] && [ -z "${ANDROID_SDK_ROOT:-}" ]; then
  printf 'ANDROID_HOME or ANDROID_SDK_ROOT must be set before building Android.\n' >&2
  exit 1
fi

ENV_FILE="$ROOT_DIR/.env.android.$MODE"
if [ ! -f "$ENV_FILE" ]; then
  printf 'Missing env file: %s\n' "$ENV_FILE" >&2
  exit 1
fi

set -a
. "$ENV_FILE"
set +a

if [ -z "${MEMOS_BASE_URL:-}" ]; then
  printf 'MEMOS_BASE_URL must be set in %s\n' "$ENV_FILE" >&2
  exit 1
fi

if [ "$MODE" = "release" ] && [ "${ALLOW_INSECURE_HTTP:-0}" = "1" ]; then
  printf 'Release builds cannot use ALLOW_INSECURE_HTTP=1\n' >&2
  exit 1
fi

cd "$ROOT_DIR"

if [ ! -d "$ROOT_DIR/node_modules" ]; then
  npm install
fi

if [ ! -d "$ROOT_DIR/src-tauri/gen/android" ]; then
  npm run tauri android init
fi

TARGET_ANDROID_DIR="$ROOT_DIR/src-tauri/gen/android"
OVERRIDES_DIR="$ROOT_DIR/src-tauri/android-overrides/app/src/main"

mkdir -p "$TARGET_ANDROID_DIR/app/src/main/java/com/memos/mobile"
sync_dir "$OVERRIDES_DIR/java/com/memos/mobile" "$TARGET_ANDROID_DIR/app/src/main/java/com/memos/mobile"
sync_dir "$OVERRIDES_DIR/res" "$TARGET_ANDROID_DIR/app/src/main/res"
cp "$OVERRIDES_DIR/AndroidManifest.xml" "$TARGET_ANDROID_DIR/app/src/main/AndroidManifest.xml"

CLEARTEXT_ALLOWED=false
if [ "$MODE" = "debug" ] && [ "${ALLOW_INSECURE_HTTP:-0}" = "1" ]; then
  CLEARTEXT_ALLOWED=true
fi

patch_cleartext_setting "$TARGET_ANDROID_DIR/app/build.gradle.kts" "$CLEARTEXT_ALLOWED"
ensure_splashscreen_dependency "$TARGET_ANDROID_DIR/app/build.gradle.kts"

if [ "$MODE" = "debug" ]; then
  npm run tauri android build -- --debug "$@"
else
  npm run tauri android build -- "$@"
fi
