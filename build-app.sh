#!/usr/bin/env bash
# Build Booker.app — a proper .app bundle so macOS treats it as a GUI app
# (clean focus/activation, launchable from Raycast/Alfred/skhd/Spotlight).
set -euo pipefail

cd "$(dirname "$0")"

APP="Booker.app"
BIN_NAME="booker"

echo "Building release binary..."
swift build -c release

echo "Assembling $APP..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp ".build/release/$BIN_NAME" "$APP/Contents/MacOS/Booker"

cat >"$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>Booker</string>
    <key>CFBundleDisplayName</key>     <string>Booker</string>
    <key>CFBundleIdentifier</key>      <string>com.meain.booker</string>
    <key>CFBundleVersion</key>         <string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleExecutable</key>      <string>Booker</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSHighResolutionCapable</key> <true/>
</dict>
</plist>
PLIST

# Ad-hoc sign so Gatekeeper/permissions attach to a stable identity.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "Done: $(pwd)/$APP"
echo "Launch with: open $(pwd)/$APP"
