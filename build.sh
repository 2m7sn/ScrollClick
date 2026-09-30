#!/bin/zsh
# Builds ScrollClick.app and ScrollClick.dmg next to this script.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/ScrollClick.app
rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "→ compiling"
swiftc -O -target arm64-apple-macos13.0 main.swift -o build/ScrollClick-arm64
swiftc -O -target x86_64-apple-macos13.0 main.swift -o build/ScrollClick-x86_64
lipo -create build/ScrollClick-arm64 build/ScrollClick-x86_64 -output "$APP/Contents/MacOS/ScrollClick"

echo "→ icon"
swift make_icon.swift build/ScrollClick.iconset
iconutil -c icns build/ScrollClick.iconset -o "$APP/Contents/Resources/ScrollClick.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>ScrollClick</string>
  <key>CFBundleDisplayName</key><string>ScrollClick</string>
  <key>CFBundleIdentifier</key><string>com.mohsen.scrollclick</string>
  <key>CFBundleExecutable</key><string>ScrollClick</string>
  <key>CFBundleIconFile</key><string>ScrollClick</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

echo "→ signing (ad-hoc)"
# identify the app by its bundle id (not the build hash) so Accessibility permission survives rebuilds
codesign --force --deep --sign - -r='designated => identifier "com.mohsen.scrollclick"' "$APP"

echo "→ dmg"
mkdir -p build/dmg
cp -R "$APP" build/dmg/
ln -s /Applications build/dmg/Applications
rm -f ScrollClick.dmg
hdiutil create -volname ScrollClick -srcfolder build/dmg -ov -format UDZO ScrollClick.dmg >/dev/null

echo "✓ done: $(pwd)/ScrollClick.dmg"
