#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SIGNING_COMMAND=(python3 -B scripts/sign-app.py)
case "${1:-}" in
  "") ;;
  --release-signing) SIGNING_COMMAND+=(--release) ;;
  *) printf '%s\n' 'Usage: scripts/package.sh [--release-signing]' >&2; exit 2 ;;
esac
if [ "$#" -gt 1 ]; then
  printf '%s\n' 'Usage: scripts/package.sh [--release-signing]' >&2
  exit 2
fi
python3 -B scripts/release_metadata.py --field version > /dev/null
swift build -c release
BINARY_DIR="$(swift build -c release --show-bin-path)"
APP_OUTPUT="$(pwd)/dist/Kestrel.app"
if [ -d "$APP_OUTPUT" ]; then
  mkdir -p dist/archive
  mv "$APP_OUTPUT" "dist/archive/Kestrel-$(date +%s)-$$.app"
fi
mkdir -p "$APP_OUTPUT/Contents/MacOS" "$APP_OUTPUT/Contents/Resources" dist/Kestrel.iconset
cp "$BINARY_DIR/Kestrel" "$APP_OUTPUT/Contents/MacOS/Kestrel"
# Remove build-machine paths from debug symbols before the final signature.
strip -S "$APP_OUTPUT/Contents/MacOS/Kestrel"
xcrun swiftc Sources/Kestrel/Brand.swift Sources/Kestrel/MaterialSurface.swift scripts/MakeIcon.swift -o dist/make-icon
dist/make-icon "$(pwd)/dist/Kestrel.iconset"
iconutil -c icns dist/Kestrel.iconset -o "$APP_OUTPUT/Contents/Resources/Kestrel.icns"
python3 -B scripts/release_metadata.py --write-plist "$APP_OUTPUT/Contents/Info.plist"
cp LICENSE "$APP_OUTPUT/Contents/Resources/LICENSE"
SPARKLE="$PWD/.build/artifacts/sparkle/Sparkle"
mkdir -p "$APP_OUTPUT/Contents/Frameworks"
ditto "$SPARKLE/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" "$APP_OUTPUT/Contents/Frameworks/Sparkle.framework"
cp "$SPARKLE/LICENSE" "$APP_OUTPUT/Contents/Resources/Sparkle-LICENSE"
codesign --verify --deep --strict "$APP_OUTPUT/Contents/Frameworks/Sparkle.framework"
python3 -B scripts/verify-package.py "$APP_OUTPUT"
"${SIGNING_COMMAND[@]}" "$APP_OUTPUT"
printf '%s\n' "$APP_OUTPUT"
