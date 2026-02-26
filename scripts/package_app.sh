#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${APP_NAME:-MicMuteBar}"
BUNDLE_ID="${BUNDLE_ID:-com.victoraji.MicMuteBar}"
MARKETING_VERSION="${MARKETING_VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
OUTPUT_DIR="${OUTPUT_DIR:-dist}"
CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$PWD/.build/clang-module-cache}"
SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-$PWD/.build/swiftpm-module-cache}"

mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE"

echo "Building release binary with swift build..."
CLANG_MODULE_CACHE_PATH="$CLANG_MODULE_CACHE_PATH" \
SWIFTPM_MODULECACHE_OVERRIDE="$SWIFTPM_MODULECACHE_OVERRIDE" \
swift build --disable-sandbox -c release --product "$APP_NAME" >/tmp/"$APP_NAME"-swift-build.log

BIN_DIR="$(
  CLANG_MODULE_CACHE_PATH="$CLANG_MODULE_CACHE_PATH" \
  SWIFTPM_MODULECACHE_OVERRIDE="$SWIFTPM_MODULECACHE_OVERRIDE" \
  swift build --disable-sandbox -c release --show-bin-path
)"
BIN_PATH="$BIN_DIR/$APP_NAME"
if [[ ! -f "$BIN_PATH" ]]; then
  echo "Expected binary not found at $BIN_PATH"
  echo "swift build log: /tmp/$APP_NAME-swift-build.log"
  exit 1
fi

APP_PATH="$OUTPUT_DIR/$APP_NAME.app"
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS"

cp "$BIN_PATH" "$APP_PATH/Contents/MacOS/$APP_NAME"

cat >"$APP_PATH/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>CFBundleShortVersionString</key>
    <string>$MARKETING_VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

echo "Signing app with identity: $CODESIGN_IDENTITY"
codesign --force --deep --sign "$CODESIGN_IDENTITY" "$APP_PATH"

echo
echo "Done:"
echo "  $APP_PATH"
echo
echo "Launch with:"
echo "  open \"$APP_PATH\""
