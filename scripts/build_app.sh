#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Token Tracker"
BUNDLE_DIR=".build/${APP_NAME}.app"
EXECUTABLE=".build/release/TokenTrackerMenuBar"
MACOS_DIR="${BUNDLE_DIR}/Contents/MacOS"
RESOURCES_DIR="${BUNDLE_DIR}/Contents/Resources"
BUILD_RELEASE_DIR="$(cd "$(dirname "${EXECUTABLE}")" && pwd -P)"

swift build -c release
rm -rf "${BUNDLE_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"
cp "${EXECUTABLE}" "${MACOS_DIR}/TokenTrackerMenuBar"
find "${BUILD_RELEASE_DIR}" -maxdepth 1 -name "TokenTrackerMenuBar_*.bundle" -exec cp -R {} "${RESOURCES_DIR}/" \;
cat > "${BUNDLE_DIR}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>TokenTrackerMenuBar</string>
  <key>CFBundleIdentifier</key>
  <string>local.token-tracker.menubar</string>
  <key>CFBundleName</key>
  <string>Token Tracker</string>
  <key>CFBundleDisplayName</key>
  <string>Token Tracker</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

echo "Built ${BUNDLE_DIR}"
