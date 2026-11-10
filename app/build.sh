#!/bin/zsh
# Builds "Swift DM.app" into ./build (no Xcode project needed).
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Swift DM.app"
ARIA2="${ARIA2:-}"
if [[ -z "$ARIA2" ]]; then
  for c in "$PWD/vendor/aria2c" "$(command -v aria2c 2>/dev/null || true)" \
           /Applications/Motrix.app/Contents/Resources/extra/darwin/$(uname -m)/aria2c; do
    [[ -n "$c" && -x "$c" ]] && { ARIA2="$c"; break; }
  done
fi
[[ -x "$ARIA2" ]] || { echo "aria2c not found. Set ARIA2=/path/to/aria2c"; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "→ Compiling"
swiftc -O -swift-version 5 -parse-as-library \
  -target "$(uname -m)-apple-macos14.0" \
  -o "$APP/Contents/MacOS/SwiftDM" Sources/*.swift

echo "→ Icon"
if [[ ! -f build/AppIcon.icns ]]; then
  python3 -I tools/make_icon.py build/AppIcon.iconset ../extension/icons
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "→ Bundling aria2 from $ARIA2"
cp "$ARIA2" "$APP/Contents/Resources/aria2c"
chmod +x "$APP/Contents/Resources/aria2c"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Swift DM</string>
  <key>CFBundleDisplayName</key><string>Swift DM</string>
  <key>CFBundleIdentifier</key><string>com.swiftdm.app</string>
  <key>CFBundleExecutable</key><string>SwiftDM</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key><string>Magnet Link</string>
      <key>CFBundleURLSchemes</key><array><string>magnet</string></array>
    </dict>
    <dict>
      <key>CFBundleURLName</key><string>Swift DM</string>
      <key>CFBundleURLSchemes</key><array><string>swiftdm</string></array>
    </dict>
  </array>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>BitTorrent File</string>
      <key>CFBundleTypeExtensions</key><array><string>torrent</string></array>
      <key>CFBundleTypeRole</key><string>Viewer</string>
    </dict>
  </array>
</dict>
</plist>
PLIST

echo "→ Signing (ad-hoc)"
codesign --force --deep --sign - "$APP" >/dev/null

echo "✓ Built $APP"
