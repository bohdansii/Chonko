#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${IMAGEOPTIM_BUILD_DIR:-$PROJECT_ROOT/.work/release-v03}"
APP_PATH="${IMAGEOPTIM_APP_PATH:-$PROJECT_ROOT/releases/Chonko-v1.0.0.app}"
export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/module-cache"
export SWIFT_MODULECACHE_PATH="$BUILD_DIR/module-cache"
swift build --package-path "$PROJECT_ROOT" --scratch-path "$BUILD_DIR" --configuration release --disable-sandbox
BIN_DIR="$(swift build --package-path "$PROJECT_ROOT" --scratch-path "$BUILD_DIR" --configuration release --show-bin-path --disable-sandbox)"
# Sign outside iCloud/File Provider directories, which may add Finder metadata during signing.
STAGING_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ImageOptimMac-build.XXXXXX")"
trap 'rm -rf "$STAGING_ROOT"' EXIT
STAGED_APP="$STAGING_ROOT/Chonko.app"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources/Codecs"
cp "$BIN_DIR/ImageOptimMac" "$STAGED_APP/Contents/MacOS/ImageOptimMac"
cp "$PROJECT_ROOT/Resources/Info.plist" "$STAGED_APP/Contents/Info.plist"
if [[ -f "$PROJECT_ROOT/design/Chonko-02-mascot.png" ]]; then
    cp "$PROJECT_ROOT/design/Chonko-02-mascot.png" "$STAGED_APP/Contents/Resources/Chonko-mascot.png"
else
    cp "$PROJECT_ROOT/design/Chonko-02-mascot.webp" "$STAGED_APP/Contents/Resources/Chonko-mascot.webp"
fi
cp "$PROJECT_ROOT/Resources/Chonko.icns" "$STAGED_APP/Contents/Resources/Chonko-v0414.icns"
cp "$PROJECT_ROOT/design/Chonko-02-logo.svg" "$STAGED_APP/Contents/Resources/Chonko-logo.svg"
cp "$PROJECT_ROOT/Resources/en.json" "$STAGED_APP/Contents/Resources/en.json"
ditto --noextattr --norsrc "$PROJECT_ROOT/Resources/Optimize in Chonko.workflow" "$STAGED_APP/Contents/Resources/Optimize in Chonko.workflow"
ditto --noextattr --norsrc "$PROJECT_ROOT/Resources/Codecs" "$STAGED_APP/Contents/Resources/Codecs"
chmod +x "$STAGED_APP/Contents/MacOS/ImageOptimMac"
for tool in cwebp ffmpeg ffprobe qpdf gs; do
    chmod +x "$STAGED_APP/Contents/Resources/Codecs/$tool"
    codesign --force --sign - --timestamp=none "$STAGED_APP/Contents/Resources/Codecs/$tool"
done
codesign --force --sign - --timestamp=none "$STAGED_APP"
codesign --verify --deep --strict "$STAGED_APP"
mkdir -p "$(dirname "$APP_PATH")"
ditto -c -k --norsrc --keepParent "$STAGED_APP" "${APP_PATH%.app}.zip"
INSTALL_ROOT="$STAGING_ROOT/Install"
mkdir -p "$INSTALL_ROOT"
ditto --noextattr --norsrc "$STAGED_APP" "$INSTALL_ROOT/Chonko.app"
ln -s /Applications "$INSTALL_ROOT/Applications"
ditto --noextattr --norsrc "$PROJECT_ROOT/Resources/Optimize in Chonko.workflow" "$INSTALL_ROOT/Optimize in Chonko.workflow"
hdiutil create -quiet -volname "Chonko" -srcfolder "$INSTALL_ROOT" -format UDZO -fs HFS+ -ov "${APP_PATH%.app}.dmg"
hdiutil verify -quiet "${APP_PATH%.app}.dmg"
echo "Готово: ${APP_PATH%.app}.dmg"
echo "Архів: ${APP_PATH%.app}.zip"
