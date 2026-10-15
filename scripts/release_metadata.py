#!/usr/bin/env python3
"""Read the release version and generate the app bundle metadata."""
import argparse
import json
from pathlib import Path
import plistlib
import re

ROOT = Path(__file__).resolve().parents[1]

# Public verification material only. The signing secret lives in macOS Keychain.
UPDATE_POLICY = {
    "SUPublicEDKey": "PFTV8NVCUW0zrvvqjBXfHFKJUFNEEZLyT6kmtdwfc00=",
    "SUFeedURL": "https://raw.githubusercontent.com/junoh-bg/kestrel/main/docs/updates/appcast.xml",
    "SUEnableAutomaticChecks": True,
    "SUAutomaticallyUpdate": False,
    "SUAllowsAutomaticUpdates": False,
    "SUSendProfileInfo": False,
    "SUVerifyUpdateBeforeExtraction": True,
    "SURequireSignedFeed": True,
}


def load_metadata(path=ROOT / "version.json"):
    value = json.loads(Path(path).read_text())
    if not isinstance(value, dict):
        raise ValueError("version.json must be an object")
    version, build = value.get("version"), value.get("build")
    if not isinstance(version, str) or not re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", version):
        raise ValueError("version must be MAJOR.MINOR.PATCH without leading zeros")
    if type(build) is not int or build < 1:
        raise ValueError("build must be a positive integer")
    return value


def write_info(path, metadata):
    info = {
        "CFBundleIdentifier": "com.localpilot.launcher",
        "CFBundleName": "Kestrel",
        "CFBundleDisplayName": "Kestrel",
        "CFBundleExecutable": "Kestrel",
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": metadata["version"],
        "CFBundleVersion": str(metadata["build"]),
        "CFBundleIconFile": "Kestrel",
        "LSMinimumSystemVersion": "14.0",
        "LSUIElement": True,
        "NSHighResolutionCapable": True,
        "NSDesktopFolderUsageDescription": "Search file names in Desktop when you choose it in Kestrel.",
        "NSDocumentsFolderUsageDescription": "Search file names in Documents when you choose it in Kestrel.",
        "NSDownloadsFolderUsageDescription": "Search file names in Downloads when you choose it in Kestrel.",
    }
    info.update(UPDATE_POLICY)
    Path(path).write_bytes(plistlib.dumps(info, sort_keys=False))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--field", choices=("version", "build"))
    mode.add_argument("--write-plist", type=Path)
    args = parser.parse_args()
    metadata = load_metadata()
    if args.field:
        print(metadata[args.field])
    else:
        write_info(args.write_plist, metadata)


if __name__ == "__main__":
    main()
