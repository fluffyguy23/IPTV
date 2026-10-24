#!/usr/bin/env bash
#
# Builds IPTVXtremePlayer.app (and optionally a .dmg) for Intel macOS.
#
# Usage:
#   Scripts/build_app.sh [--debug] [--dmg] [--vlc /path/to/VLC.app]
#
# Requirements: Xcode Command Line Tools (swiftc/clang) and VLC.app installed
# (used for libVLC headers, dylibs, and plugins — bundled into the .app so the
# result is self-contained and does not require VLC to remain installed).
#
# NOTE: run this in a normal terminal, not inside a restricted sandbox — the
# Swift/Clang toolchain needs to write to the system temp directory.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VLC_APP="/Applications/VLC.app"
# Optional repository-root .env (build settings only; see .env.example).
if [[ -f "$ROOT/../.env" ]]; then
  ENV_VLC="$(grep -E '^VLC_APP_PATH=' "$ROOT/../.env" | tail -1 | cut -d= -f2- || true)"
  if [[ -n "$ENV_VLC" ]]; then VLC_APP="$ENV_VLC"; fi
fi
CONFIG="release"
MAKE_DMG=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug) CONFIG="debug"; shift;;
    --dmg) MAKE_DMG=1; shift;;
    --vlc) VLC_APP="$2"; shift 2;;
    *) echo "Unknown option: $1"; exit 1;;
  esac
done

if [[ ! -d "$VLC_APP" ]]; then
  echo "error: VLC.app not found at $VLC_APP (pass --vlc /path/to/VLC.app)"
  exit 1
fi

SDK="$(xcrun --show-sdk-path)"
VLC_INC="$VLC_APP/Contents/MacOS/include"
VLC_LIB="$VLC_APP/Contents/MacOS/lib"
VLC_PLUGINS="$VLC_APP/Contents/MacOS/plugins"
TARGET="x86_64-apple-macosx12.0"

BUILD="$ROOT/build"
DIST="$ROOT/dist"
APP="$DIST/IPTVXtremePlayer.app"
EXE_NAME="IPTVXtremePlayer"

echo "==> Clean"
rm -rf "$BUILD" "$APP"
mkdir -p "$BUILD"

echo "==> Compile VLC bridge (C)"
clang -c "$ROOT/Sources/VLCBridge/VLCBridge.c" \
  -o "$BUILD/VLCBridge.o" \
  -I "$ROOT/Sources/VLCBridge/include" \
  -I "$VLC_INC" \
  -isysroot "$SDK" -arch x86_64 -mmacosx-version-min=12.0 -O2

echo "==> Compile Swift ($CONFIG)"
OPT=(-Onone -g)
[[ "$CONFIG" == "release" ]] && OPT=(-O)

# Collect Swift sources safely (the project path may contain spaces).
SWIFT_FILES=()
while IFS= read -r -d '' f; do SWIFT_FILES+=("$f"); done \
  < <(find "$ROOT/Sources/IPTVXtremePlayer" -name '*.swift' -print0)

swiftc "${OPT[@]}" \
  -sdk "$SDK" -target "$TARGET" \
  -import-objc-header "$ROOT/Sources/VLCBridge/include/VLCBridge.h" \
  "${SWIFT_FILES[@]}" \
  "$BUILD/VLCBridge.o" \
  -L "$VLC_LIB" -lvlc \
  -Xlinker -rpath -Xlinker "@executable_path/../Frameworks" \
  -Xlinker -rpath -Xlinker "$VLC_LIB" \
  -o "$BUILD/$EXE_NAME" \
  -framework AppKit -framework Foundation

echo "==> Assemble .app bundle"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BUILD/$EXE_NAME" "$APP/Contents/MacOS/$EXE_NAME"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                 <string>IPTVXtremePlayer</string>
    <key>CFBundleDisplayName</key>          <string>IPTVXtremePlayer</string>
    <key>CFBundleIdentifier</key>           <string>com.iptvxtreme.player</string>
    <key>CFBundleExecutable</key>           <string>IPTVXtremePlayer</string>
    <key>CFBundlePackageType</key>          <string>APPL</string>
    <key>CFBundleShortVersionString</key>   <string>1.2.1</string>
    <key>CFBundleVersion</key>              <string>4</string>
    <key>LSMinimumSystemVersion</key>       <string>12.0</string>
    <key>NSHighResolutionCapable</key>      <true/>
    <key>LSApplicationCategoryType</key>    <string>public.app-category.entertainment</string>
    <key>NSHumanReadableCopyright</key>     <string>IPTVXtremePlayer</string>
    <!-- IPTV servers are frequently plain HTTP; allow non-TLS connections. -->
    <key>NSAppTransportSecurity</key>
    <dict><key>NSAllowsArbitraryLoads</key><true/></dict>
</dict>
</plist>
PLIST

echo "==> Bundle libVLC (self-contained)"
# Preserve symlinks (libvlc.dylib -> libvlc.5.dylib, etc.)
cp -a "$VLC_LIB/." "$APP/Contents/Frameworks/"
cp -a "$VLC_PLUGINS" "$APP/Contents/Frameworks/plugins"

echo "==> Ad-hoc code signing"
codesign --force --deep --sign - "$APP" 2>/dev/null || \
  echo "   (codesign skipped/failed — app still runs; right-click > Open on first launch)"

echo "==> Done: $APP"

if [[ "$MAKE_DMG" == "1" ]]; then
  echo "==> Build .dmg"
  DMG="$DIST/IPTVXtremePlayer.dmg"
  rm -f "$DMG"
  STAGING="$(mktemp -d)"
  cp -R "$APP" "$STAGING/"
  ln -s /Applications "$STAGING/Applications"
  hdiutil create -volname "IPTVXtremePlayer" -srcfolder "$STAGING" \
    -ov -format UDZO "$DMG" >/dev/null
  rm -rf "$STAGING"
  echo "==> Done: $DMG"
fi

echo ""
echo "Launch with:  open \"$APP\""
