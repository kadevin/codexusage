#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/CodexUsage.app"
ICONSET="$ROOT/build/CodexUsage.iconset"
ICON="$ROOT/build/CodexUsage.icns"
VERSION="${APP_VERSION:-$(tr -d '[:space:]' < "$ROOT/VERSION")}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git -C "$ROOT" rev-list --count HEAD)}"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid app version: $VERSION" >&2
  exit 1
fi
if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "Invalid build number: $BUILD_NUMBER" >&2
  exit 1
fi

cd "$ROOT"
if [[ -n "${PREBUILT_BINARY:-}" ]]; then
  BIN="$PREBUILT_BINARY"
  test -x "$BIN"
else
  SWIFT_BUILD_FLAGS=()
  if [[ "${CODEXUSAGE_DISABLE_SWIFT_SANDBOX:-0}" == "1" ]]; then
    SWIFT_BUILD_FLAGS+=(--disable-sandbox)
  fi
  swift build -c release "${SWIFT_BUILD_FLAGS[@]}"
  BIN="$ROOT/.build/release/CodexUsage"
fi
swift "$ROOT/scripts/generate-app-icon.swift" "$ICONSET" "$ICON"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/CodexUsage"
cp "$ICON" "$APP/Contents/Resources/CodexUsage.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>CodexUsage</string>
  <key>CFBundleIdentifier</key>
  <string>local.codexusage.app</string>
  <key>CFBundleIconFile</key>
  <string>CodexUsage</string>
  <key>CFBundleName</key>
  <string>CodexUsage</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null
codesign --force --deep --sign - "$APP"
echo "$APP"
