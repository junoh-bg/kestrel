#!/bin/bash
# Prepare a preview archive locally. This never uploads or publishes a release.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -B -m unittest discover -s Tests/Packaging -v
VERSION="$(python3 -B scripts/release_metadata.py --field version)"
scripts/package.sh --release-signing
if [ "$(lipo -archs dist/Kestrel.app/Contents/MacOS/Kestrel)" != arm64 ]; then
  printf '%s\n' 'The current download supports Apple silicon only.' >&2
  exit 1
fi
mkdir -p dist/releases
RELEASE_DIR="$(mktemp -d "$PWD/dist/releases/$VERSION-XXXXXX")"
mkdir "$RELEASE_DIR/payload"
ditto dist/Kestrel.app "$RELEASE_DIR/payload/Kestrel.app"
cp docs/INSTALL.txt "$RELEASE_DIR/payload/START-HERE.txt"
cp LICENSE "$RELEASE_DIR/payload/LICENSE.txt"
cp "docs/releases/$VERSION.md" "$RELEASE_DIR/payload/RELEASE-NOTES.txt"
ARCHIVE="Kestrel-$VERSION-macos-arm64.zip"
ditto -c -k --sequesterRsrc "$RELEASE_DIR/payload" "$RELEASE_DIR/$ARCHIVE"
(cd "$RELEASE_DIR" && shasum -a 256 "$ARCHIVE" > "$ARCHIVE.sha256")
printf '%s\n' "$RELEASE_DIR/$ARCHIVE"
