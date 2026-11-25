#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="TextLens"
APP_BUNDLE="TextLens.app"
SDK="$(xcrun --show-sdk-path)"
ARCH="$(uname -m)"
TARGET="${ARCH}-apple-macos14.0"

echo "==> 编译 TextLens ($TARGET)"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

swiftc \
  -O \
  -swift-version 5 \
  -target "$TARGET" \
  -sdk "$SDK" \
  Sources/*.swift \
  -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME" \
  -framework AppKit \
  -framework SwiftUI \
  -framework Quartz \
  -framework QuickLookUI \
  -framework UniformTypeIdentifiers \
  -liconv

cp Resources/Info.plist "$APP_BUNDLE/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

# Ad-hoc signature is enough for a locally built app and makes Finder integration reliable.
codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null 2>&1 || true
touch "$APP_BUNDLE"

# Make the app discoverable in "Open With" and drag-to-Dock flows.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [ -x "$LSREGISTER" ]; then
  "$LSREGISTER" -f "$(pwd)/$APP_BUNDLE" >/dev/null 2>&1 || true
fi

echo "==> 完成：$(pwd)/$APP_BUNDLE"
if [ "${1:-}" = "--run" ]; then
  open "$APP_BUNDLE"
fi
