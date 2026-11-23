#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
: "${ANDROID_HOME:?Set ANDROID_HOME to the Android SDK directory}"
: "${JAVA_HOME:?Set JAVA_HOME to a JDK directory}"
godot="${GODOT_BIN:-godot}"
debug_keystore="${GODOT_ANDROID_KEYSTORE_DEBUG_PATH:-$HOME/.android/debug.keystore}"
mkdir -p "$(dirname "$debug_keystore")" build
if [[ ! -f "$debug_keystore" ]]; then
  keytool -genkeypair -keystore "$debug_keystore" -storepass android \
    -keypass android -alias androiddebugkey -keyalg RSA -keysize 2048 \
    -validity 10000 -dname 'CN=Son Hat Test'
fi

temp_config="$(mktemp -d)"
trap 'rm -rf -- "$temp_config"' EXIT
export XDG_CONFIG_HOME="$temp_config"
settings="$XDG_CONFIG_HOME/godot"
mkdir -p "$settings"
cat > "$settings/editor_settings-4.3.tres" <<SETTINGS
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/android_sdk_path = "$ANDROID_HOME"
export/android/java_sdk_path = "$JAVA_HOME"
export/android/debug_keystore = "$debug_keystore"
SETTINGS

export GODOT_ANDROID_KEYSTORE_DEBUG_PATH="$debug_keystore"
export GODOT_ANDROID_KEYSTORE_DEBUG_USER=androiddebugkey
export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD=android

python3 tools/generate_assets.py
"$godot" --headless --editor --import
"$godot" --headless --path . --quit-after 180 -- --verify | tee build/verify.log
grep -F 'ALL GODOT 4.3 HEADLESS VERIFICATION TESTS PASSED!' build/verify.log
"$godot" --headless --path . --export-debug Android build/Son-Hat.apk
