#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
FAILURES=0

pass() {
  printf 'ok   %s\n' "$1"
}

warn() {
  printf 'warn %s\n' "$1"
}

fail() {
  printf 'fail %s\n' "$1"
  FAILURES=1
}

check_command() {
  if command -v "$1" >/dev/null 2>&1; then
    pass "found command: $1"
  else
    fail "missing command: $1"
  fi
}

check_file() {
  if [ -f "$1" ]; then
    pass "found file: $1"
  else
    fail "missing file: $1"
  fi
}

printf 'Checking Memos Mobile Android prerequisites in %s\n' "$ROOT_DIR"

check_command node
check_command npm
check_command cargo
check_command rustup
check_command java
check_command adb

if [ -n "${ANDROID_HOME:-}" ] || [ -n "${ANDROID_SDK_ROOT:-}" ]; then
  pass "Android SDK environment variable is set"
else
  fail "ANDROID_HOME or ANDROID_SDK_ROOT must be set"
fi

check_file "$ROOT_DIR/.env.android.debug"
check_file "$ROOT_DIR/.env.android.release"
check_file "$ROOT_DIR/src-tauri/tauri.conf.json"
check_file "$ROOT_DIR/src-tauri/android-overrides/app/src/main/java/com/memos/mobile/MainActivity.kt"

if command -v rustup >/dev/null 2>&1; then
  INSTALLED_TARGETS=$(rustup target list --installed 2>/dev/null || true)
  echo "$INSTALLED_TARGETS" | grep -q '^aarch64-linux-android$' \
    && pass "Rust target installed: aarch64-linux-android" \
    || fail "missing Rust target: aarch64-linux-android"
fi

if grep -q '^MEMOS_BASE_URL=' "$ROOT_DIR/.env.android.debug"; then
  pass ".env.android.debug defines MEMOS_BASE_URL"
else
  fail ".env.android.debug must define MEMOS_BASE_URL"
fi

if grep -q '^MEMOS_BASE_URL=' "$ROOT_DIR/.env.android.release"; then
  pass ".env.android.release defines MEMOS_BASE_URL"
else
  fail ".env.android.release must define MEMOS_BASE_URL"
fi

if grep -q '^MEMOS_BASE_URL=http://' "$ROOT_DIR/.env.android.release"; then
  fail "release env file cannot use http://"
else
  pass "release env file does not opt into insecure HTTP"
fi

if [ ! -d "$ROOT_DIR/src-tauri/gen/android" ]; then
  warn "src-tauri/gen/android has not been initialized yet; scripts/build-android.sh will create it"
else
  pass "src-tauri/gen/android is present"
fi

if [ "$FAILURES" -ne 0 ]; then
  printf '\nDoctor found missing prerequisites.\n'
  exit 1
fi

printf '\nDoctor finished without blocking issues.\n'
