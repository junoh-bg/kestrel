#!/bin/bash
# Exercise legacy and current AppKit rendering, independently of the test runner's SDK.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p dist/visual-checks
OUTPUT="$(mktemp -d "$PWD/dist/visual-checks/controls-XXXXXX")"
ARCH="$(uname -m)"
for MODE in legacy current; do
  FLAGS=(-target "$ARCH-apple-macos14.0")
  if [ "$MODE" = legacy ]; then
    FLAGS+=(-Xlinker -platform_version -Xlinker macos -Xlinker 14.0 -Xlinker 14.0)
  fi
  xcrun swiftc "${FLAGS[@]}" \
    Sources/Kestrel/Brand.swift Sources/Kestrel/MaterialSurface.swift \
    Tests/Visual/ControlContrast.swift -o "$OUTPUT/$MODE"
  "$OUTPUT/$MODE"
done
