#!/usr/bin/env python3
"""Validate the shipped identity and every icon's actual pixel dimensions."""
import plistlib
import re
import struct
import sys
from pathlib import Path

from release_metadata import load_metadata, UPDATE_POLICY

app = Path(sys.argv[1])
info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
errors = []
binary = (app / "Contents/MacOS/Kestrel").read_bytes()
source_root = str(Path(__file__).resolve().parents[1]).encode()
if source_root in binary:
    errors.append("Executable contains build-machine source paths; strip debug symbols before signing")
for key, expected in UPDATE_POLICY.items():
    if info.get(key) != expected:
        errors.append(f"Updater policy mismatch: {key}")
framework = app / "Contents/Frameworks/Sparkle.framework"
if not (framework / "Sparkle").is_file() or not (framework / "Versions/Current").is_symlink():
    errors.append("Sparkle framework is missing or its symlinks were not preserved")
if not (app / "Contents/Resources/Sparkle-LICENSE").is_file():
    errors.append("Missing Sparkle license")
metadata = load_metadata()
if info.get("CFBundleShortVersionString") != metadata["version"]:
    errors.append("App version does not match version.json")
if info.get("CFBundleVersion") != str(metadata["build"]):
    errors.append("App build does not match version.json")
license_file = Path(__file__).resolve().parents[1] / "LICENSE"
if (app / "Contents/Resources/LICENSE").read_bytes() != license_file.read_bytes():
    errors.append("Bundle license differs from the source license")
for key in ("CFBundleName", "CFBundleDisplayName", "CFBundleExecutable", "CFBundleIconFile"):
    if info.get(key) != "Kestrel":
        errors.append(f"{key}: expected Kestrel, got {info.get(key)!r}")
if info.get("CFBundleIdentifier") != "com.localpilot.launcher":
    errors.append("Legacy bundle identity must remain stable for existing installations")
if {p.name for p in (app / "Contents/MacOS").iterdir()} != {"Kestrel"}:
    errors.append("Bundle must contain only the Kestrel executable")
if not (app / "Contents/Resources/Kestrel.icns").is_file():
    errors.append("Missing Kestrel icon resource")
icons = app.parent / "Kestrel.iconset"
for icon in sorted(icons.glob("*.png")):
    match = re.fullmatch(r"icon_(\d+)x\d+(@2x)?\.png", icon.name)
    if not match:
        errors.append(f"Unexpected icon file {icon.name}")
        continue
    expected = int(match[1]) * (2 if match[2] else 1)
    data = icon.read_bytes()
    actual = struct.unpack(">II", data[16:24])
    if actual != (expected, expected):
        errors.append(f"{icon.name}: expected {expected}px, got {actual}")
if len(list(icons.glob("*.png"))) != 10:
    errors.append("Expected ten icon representations")
if errors:
    sys.exit("\n".join(errors))
print("Kestrel package identity and ten icon dimensions verified")
