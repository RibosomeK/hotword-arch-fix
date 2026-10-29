#!/usr/bin/env bash
# Build the Hotword Arch Fix LSPosed module.
#
# Requirements:
#   - JDK 17+ (javac, jar, keytool)
#   - Android SDK Platform 36 (android.jar)
#   - Android build-tools (aapt2, d8, zipalign, apksigner)
#   - Python 3
#   - libs/api-82.jar (Xposed API 82, included in this repo)
#
# Example (adapt paths to your SDK):
#   ANDROID_HOME=$HOME/Android/Sdk ./build.sh
#   ANDROID_JAR=/path/to/android-36/android.jar \
#   BUILD_TOOLS=/path/to/build-tools/36.0.0 ./build.sh
set -euo pipefail

MODULE_NAME="HotwordArchFix"
MIN_SDK="${MIN_SDK:-26}"
TARGET_SDK="${TARGET_SDK:-36}"
OUT="${OUT:-build}"
MANIFEST="${MANIFEST:-AndroidManifest.xml}"
XPOSED_JAR="${XPOSED_JAR:-libs/api-82.jar}"
KEYSTORE="${KEYSTORE:-keystore/debug.keystore}"
KS_PASS="${KS_PASS:-android}"
KEY_ALIAS="${KEY_ALIAS:-androiddebugkey}"
KEY_PASS="${KEY_PASS:-android}"

if [ -n "${JAVA_HOME:-}" ]; then
    PATH="$JAVA_HOME/bin:$PATH"
fi
JAVAC="${JAVAC:-javac}"
JAR="${JAR:-jar}"
KEYTOOL="${KEYTOOL:-keytool}"
PYTHON="${PYTHON:-python3}"

ANDROID_JAR="${ANDROID_JAR:-${ANDROID_HOME:-/nonexistent}/platforms/android-$TARGET_SDK/android.jar}"
if [ -z "${BUILD_TOOLS:-}" ] && [ -n "${ANDROID_HOME:-}" ]; then
    BUILD_TOOLS="$(find "$ANDROID_HOME/build-tools" -mindepth 1 -maxdepth 1 -type d 2>/dev/null \
        | sort -V | tail -n1 || true)"
fi
BUILD_TOOLS="${BUILD_TOOLS:-}"
AAPT2="${AAPT2:-$BUILD_TOOLS/aapt2}"
D8="${D8:-$BUILD_TOOLS/d8}"
ZIPALIGN="${ZIPALIGN:-$BUILD_TOOLS/zipalign}"
APKSIGNER="${APKSIGNER:-$BUILD_TOOLS/apksigner}"

die() {
    echo "error: $*" >&2
    exit 1
}

for tool in "$JAVAC" "$JAR" "$KEYTOOL" "$PYTHON"; do
    command -v "$tool" >/dev/null 2>&1 || die "missing $tool (set JAVA_HOME or PATH)"
done
[ -f "$ANDROID_JAR" ] || die "ANDROID_JAR not found: $ANDROID_JAR (set ANDROID_HOME or ANDROID_JAR)"
[ -x "$AAPT2" ] || die "aapt2 not found (set BUILD_TOOLS or AAPT2)"
[ -x "$D8" ] || die "d8 not found (set BUILD_TOOLS or D8)"
[ -x "$ZIPALIGN" ] || die "zipalign not found (set BUILD_TOOLS or ZIPALIGN)"
[ -x "$APKSIGNER" ] || die "apksigner not found (set BUILD_TOOLS or APKSIGNER)"
[ -f "$XPOSED_JAR" ] || die "missing Xposed API jar: $XPOSED_JAR"
[ -f "$MANIFEST" ] || die "missing $MANIFEST (run from the repo root)"

rm -rf "$OUT"
mkdir -p "$OUT/classes" "$OUT/dex"

mapfile -t SOURCES < <(find src -name '*.java' | sort)
[ "${#SOURCES[@]}" -gt 0 ] || die "no Java sources found under src/"

"$JAVAC" -source 8 -target 8 -encoding UTF-8 \
    -classpath "$ANDROID_JAR:$XPOSED_JAR" \
    -d "$OUT/classes" "${SOURCES[@]}"

"$JAR" cf "$OUT/classes.jar" -C "$OUT/classes" .
"$D8" --lib "$ANDROID_JAR" --lib "$XPOSED_JAR" \
    --min-api "$MIN_SDK" --output "$OUT/dex" "$OUT/classes.jar"

"$AAPT2" compile --dir res -o "$OUT/res.zip"
"$AAPT2" link -o "$OUT/base.apk" -I "$ANDROID_JAR" \
    --manifest "$MANIFEST" -A assets \
    --min-sdk-version "$MIN_SDK" --target-sdk-version "$TARGET_SDK" \
    "$OUT/res.zip"

"$PYTHON" - "$OUT/base.apk" "$OUT/dex/classes.dex" <<'PY'
import sys
import zipfile

apk, dex = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(apk, "a") as z:
    z.write(dex, "classes.dex")
PY

"$ZIPALIGN" -f 4 "$OUT/base.apk" "$OUT/aligned.apk"

if [ ! -f "$KEYSTORE" ]; then
    echo "keystore not found; generating a debug-only key at $KEYSTORE"
    mkdir -p "$(dirname "$KEYSTORE")"
    "$KEYTOOL" -genkeypair -v \
        -keystore "$KEYSTORE" -storepass "$KS_PASS" -keypass "$KEY_PASS" \
        -alias "$KEY_ALIAS" -keyalg RSA -keysize 2048 -validity 10000 \
        -dname "CN=Android Debug,O=Android,C=US" >/dev/null
fi

rm -f "$OUT/$MODULE_NAME.apk"
"$APKSIGNER" sign \
    --ks "$KEYSTORE" --ks-pass "pass:$KS_PASS" --key-pass "pass:$KEY_PASS" \
    --ks-key-alias "$KEY_ALIAS" \
    --out "$OUT/$MODULE_NAME.apk" "$OUT/aligned.apk"

echo
echo "built: $OUT/$MODULE_NAME.apk"
sha256sum "$OUT/$MODULE_NAME.apk"
