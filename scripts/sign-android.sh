#!/usr/bin/env sh
set -eu

usage() {
  cat <<'EOF'
Usage:
  ./scripts/sign-android.sh <unsigned-apk> [signed-apk]

Environment:
  ANDROID_HOME / ANDROID_SDK_ROOT      Android SDK root
  JAVA_HOME                            Java home used to locate keytool
  ANDROID_KEYSTORE_FILE                Existing keystore file path
  ANDROID_KEYSTORE_TYPE                Keystore type (for example JKS or PKCS12)
  ANDROID_KEY_ALIAS                    Keystore alias
  ANDROID_KEYSTORE_PASSWORD            Keystore password
  ANDROID_KEY_PASSWORD                 Key password

If no keystore env vars are provided, the script generates a temporary
test keystore so CI can still produce an installable APK artifact.
EOF
}

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
  usage
  exit 1
fi

INPUT_APK=$1
if [ ! -f "$INPUT_APK" ]; then
  printf 'Unsigned APK not found: %s\n' "$INPUT_APK" >&2
  exit 1
fi

case "$INPUT_APK" in
  *-unsigned.apk)
    DEFAULT_SIGNED_APK=${INPUT_APK%-unsigned.apk}-signed.apk
    DEFAULT_ALIGNED_APK=${INPUT_APK%-unsigned.apk}-aligned.apk
    ;;
  *.apk)
    DEFAULT_SIGNED_APK=${INPUT_APK%.apk}-signed.apk
    DEFAULT_ALIGNED_APK=${INPUT_APK%.apk}-aligned.apk
    ;;
  *)
    printf 'Expected an .apk input file, got: %s\n' "$INPUT_APK" >&2
    exit 1
    ;;
esac

SIGNED_APK=${2:-$DEFAULT_SIGNED_APK}
ALIGNED_APK=$DEFAULT_ALIGNED_APK

SDK_ROOT=${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}
if [ -z "$SDK_ROOT" ]; then
  printf 'ANDROID_HOME or ANDROID_SDK_ROOT must be set before signing.\n' >&2
  exit 1
fi

resolve_tool() {
  BASE=$1
  for CANDIDATE in "$BASE" "$BASE.exe" "$BASE.bat"; do
    if [ -f "$CANDIDATE" ]; then
      printf '%s\n' "$CANDIDATE"
      return 0
    fi
  done
  return 1
}

if [ -n "${ANDROID_BUILD_TOOLS_DIR:-}" ]; then
  BUILD_TOOLS_DIR=$ANDROID_BUILD_TOOLS_DIR
else
  BUILD_TOOLS_DIR=$(find "$SDK_ROOT/build-tools" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1)
fi

if [ -z "$BUILD_TOOLS_DIR" ] || [ ! -d "$BUILD_TOOLS_DIR" ]; then
  printf 'Unable to locate Android build-tools under %s\n' "$SDK_ROOT" >&2
  exit 1
fi

ZIPALIGN=$(resolve_tool "$BUILD_TOOLS_DIR/zipalign") || {
  printf 'Unable to find zipalign in %s\n' "$BUILD_TOOLS_DIR" >&2
  exit 1
}
APKSIGNER=$(resolve_tool "$BUILD_TOOLS_DIR/apksigner") || {
  printf 'Unable to find apksigner in %s\n' "$BUILD_TOOLS_DIR" >&2
  exit 1
}

if [ -n "${JAVA_HOME:-}" ] && [ -f "$JAVA_HOME/bin/keytool" ]; then
  KEYTOOL="$JAVA_HOME/bin/keytool"
elif [ -n "${JAVA_HOME:-}" ] && [ -f "$JAVA_HOME/bin/keytool.exe" ]; then
  KEYTOOL="$JAVA_HOME/bin/keytool.exe"
else
  KEYTOOL=$(command -v keytool || true)
fi

if [ -z "$KEYTOOL" ]; then
  printf 'Unable to find keytool. Set JAVA_HOME or add keytool to PATH.\n' >&2
  exit 1
fi

TEMP_DIR=
if [ -n "${ANDROID_KEYSTORE_FILE:-}" ]; then
  if [ ! -f "$ANDROID_KEYSTORE_FILE" ]; then
    printf 'Keystore file not found: %s\n' "$ANDROID_KEYSTORE_FILE" >&2
    exit 1
  fi
  : "${ANDROID_KEY_ALIAS:?ANDROID_KEY_ALIAS is required when using ANDROID_KEYSTORE_FILE}"
  : "${ANDROID_KEYSTORE_PASSWORD:?ANDROID_KEYSTORE_PASSWORD is required when using ANDROID_KEYSTORE_FILE}"
  : "${ANDROID_KEY_PASSWORD:?ANDROID_KEY_PASSWORD is required when using ANDROID_KEYSTORE_FILE}"
else
  TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/memos-mobile-sign.XXXXXX")
  ANDROID_KEYSTORE_FILE="$TEMP_DIR/memos-mobile-ci.keystore"
  ANDROID_KEYSTORE_TYPE=${ANDROID_KEYSTORE_TYPE:-PKCS12}
  ANDROID_KEY_ALIAS=${ANDROID_KEY_ALIAS:-memos-mobile-ci}
  ANDROID_KEYSTORE_PASSWORD=${ANDROID_KEYSTORE_PASSWORD:-memosmobile}
  ANDROID_KEY_PASSWORD=${ANDROID_KEY_PASSWORD:-memosmobile}

  printf 'No signing secrets provided. Generating a temporary test keystore.\n' >&2
  "$KEYTOOL" -genkeypair -v \
    -keystore "$ANDROID_KEYSTORE_FILE" \
    -storetype "$ANDROID_KEYSTORE_TYPE" \
    -storepass "$ANDROID_KEYSTORE_PASSWORD" \
    -keypass "$ANDROID_KEY_PASSWORD" \
    -alias "$ANDROID_KEY_ALIAS" \
    -keyalg RSA \
    -keysize 4096 \
    -validity 3650 \
    -dname "CN=Memos Mobile CI, OU=GitHub Actions, O=Local, L=Shanghai, ST=Shanghai, C=CN" \
    -noprompt >/dev/null
fi

rm -f "$ALIGNED_APK" "$SIGNED_APK"

"$ZIPALIGN" -f -p 4 "$INPUT_APK" "$ALIGNED_APK"
if [ -n "${ANDROID_KEYSTORE_TYPE:-}" ]; then
  "$APKSIGNER" sign \
    --ks "$ANDROID_KEYSTORE_FILE" \
    --ks-type "$ANDROID_KEYSTORE_TYPE" \
    --ks-key-alias "$ANDROID_KEY_ALIAS" \
    --ks-pass "pass:$ANDROID_KEYSTORE_PASSWORD" \
    --key-pass "pass:$ANDROID_KEY_PASSWORD" \
    --out "$SIGNED_APK" \
    "$ALIGNED_APK"
else
  "$APKSIGNER" sign \
    --ks "$ANDROID_KEYSTORE_FILE" \
    --ks-key-alias "$ANDROID_KEY_ALIAS" \
    --ks-pass "pass:$ANDROID_KEYSTORE_PASSWORD" \
    --key-pass "pass:$ANDROID_KEY_PASSWORD" \
    --out "$SIGNED_APK" \
    "$ALIGNED_APK"
fi
"$APKSIGNER" verify --verbose "$SIGNED_APK" >/dev/null

printf 'Signed APK: %s\n' "$SIGNED_APK"

if [ -n "$TEMP_DIR" ]; then
  printf 'Temporary keystore was used for this signing run.\n' >&2
fi
