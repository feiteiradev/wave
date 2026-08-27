#!/bin/bash
# Builds Wave.app from the Swift package and signs it.
#
# TCC keys Microphone and Accessibility grants to the code-signing identity and
# bundle ID. Both are stable here on purpose: an ad-hoc signature changes on
# every build, which would silently revoke Accessibility each time and mean
# re-approving Wave in System Settings after every rebuild.
set -euo pipefail

CONFIGURATION="${CONFIGURATION:-release}"
BUNDLE_ID="${BUNDLE_ID:-com.pedrofeiteira.Wave}"
APP_NAME="Wave"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/$APP_NAME.app"

# Any Apple Development identity in the keychain; override with SIGN_IDENTITY.
if [ -z "${SIGN_IDENTITY:-}" ]; then
  SIGN_IDENTITY=$(security find-identity -v -p codesigning \
    | grep "Apple Development" | head -1 | sed -E 's/.*"(.*)"/\1/')
fi

echo "==> Building ($CONFIGURATION)"
swift build -c "$CONFIGURATION" --product "$APP_NAME"
BINARY="$(swift build -c "$CONFIGURATION" --product "$APP_NAME" --show-bin-path)/$APP_NAME"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <!-- Menu-bar utility: no Dock icon, no main window (PRD 24). -->
    <key>LSUIElement</key><true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Wave records your voice while you hold the dictation hotkey. Audio is processed on this Mac and never saved or uploaded.</string>
    <key>NSHumanReadableCopyright</key><string>Wave</string>
</dict>
</plist>
PLIST

cat > "$ROOT/build/Wave.entitlements" <<ENTITLEMENTS
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Not sandboxed: inserting text into other applications through the
         Accessibility API is incompatible with the App Sandbox. -->
    <key>com.apple.security.automation.apple-events</key><true/>
    <key>com.apple.security.device.audio-input</key><true/>
</dict>
</plist>
ENTITLEMENTS

if [ -n "$SIGN_IDENTITY" ]; then
  echo "==> Signing with: $SIGN_IDENTITY"
  codesign --force --deep --options runtime \
    --entitlements "$ROOT/build/Wave.entitlements" \
    --sign "$SIGN_IDENTITY" "$APP"
  codesign --verify --verbose=2 "$APP"
else
  echo "!! No Apple Development identity found."
  echo "!! Falling back to an ad-hoc signature: macOS will drop the"
  echo "!! Accessibility grant on every rebuild. Set SIGN_IDENTITY to fix."
  codesign --force --deep --sign - "$APP"
fi

echo "==> Built $APP"
