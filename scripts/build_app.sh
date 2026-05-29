#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Token Tracker"
BUNDLE_DIR=".build/${APP_NAME}.app"
EXECUTABLE=".build/release/TokenTrackerMenuBar"
APP_ICON_SOURCE="Sources/TokenTrackerMenuBar/Resources/AppIcon.png"
APP_ICONSET_DIR=".build/AppIcon.iconset"
APP_ICON_FILE="AppIcon.icns"
MACOS_DIR="${BUNDLE_DIR}/Contents/MacOS"
RESOURCES_DIR="${BUNDLE_DIR}/Contents/Resources"

swift build -c release
BUILD_RELEASE_DIR="$(cd "$(dirname "${EXECUTABLE}")" && pwd -P)"
rm -rf "${BUNDLE_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"
cp "${EXECUTABLE}" "${MACOS_DIR}/TokenTrackerMenuBar"
find "${BUILD_RELEASE_DIR}" -maxdepth 1 -name "TokenTrackerMenuBar_*.bundle" -exec cp -R {} "${RESOURCES_DIR}/" \;

if [[ -f "${APP_ICON_SOURCE}" ]]; then
  rm -rf "${APP_ICONSET_DIR}"
  mkdir -p "${APP_ICONSET_DIR}"
  sips -z 16 16 "${APP_ICON_SOURCE}" --out "${APP_ICONSET_DIR}/icon_16x16.png" >/dev/null
  sips -z 32 32 "${APP_ICON_SOURCE}" --out "${APP_ICONSET_DIR}/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "${APP_ICON_SOURCE}" --out "${APP_ICONSET_DIR}/icon_32x32.png" >/dev/null
  sips -z 64 64 "${APP_ICON_SOURCE}" --out "${APP_ICONSET_DIR}/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "${APP_ICON_SOURCE}" --out "${APP_ICONSET_DIR}/icon_128x128.png" >/dev/null
  sips -z 256 256 "${APP_ICON_SOURCE}" --out "${APP_ICONSET_DIR}/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "${APP_ICON_SOURCE}" --out "${APP_ICONSET_DIR}/icon_256x256.png" >/dev/null
  sips -z 512 512 "${APP_ICON_SOURCE}" --out "${APP_ICONSET_DIR}/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "${APP_ICON_SOURCE}" --out "${APP_ICONSET_DIR}/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "${APP_ICON_SOURCE}" --out "${APP_ICONSET_DIR}/icon_512x512@2x.png" >/dev/null
  iconutil -c icns "${APP_ICONSET_DIR}" -o "${RESOURCES_DIR}/${APP_ICON_FILE}"
fi

cat > "${BUNDLE_DIR}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>TokenTrackerMenuBar</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
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
