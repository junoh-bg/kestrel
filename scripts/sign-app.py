#!/usr/bin/env python3
"""Sign a local app, or require the pinned Keychain identity for release builds."""
import argparse
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def sign_app(app, release=False):
    policy = json.loads((ROOT / 'config/code-signing.json').read_text())
    fingerprint = policy['certificate_sha1']
    identifier = policy['bundle_identifier']
    if not re.fullmatch(r'[0-9A-F]{40}', fingerprint):
        raise ValueError('Invalid public signing certificate fingerprint')
    if not re.fullmatch(r'[A-Za-z0-9.-]+', identifier):
        raise ValueError('Invalid signing bundle identifier')
    app = Path(app).resolve()
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != identifier:
        raise ValueError('Unexpected app bundle identifier')
    # Pin the leaf certificate, never an identifier-only requirement. Trust-store
    # changes are unnecessary: this establishes continuity, not Gatekeeper trust.
    requirement = f'identifier "{identifier}" and certificate leaf = H"{fingerprint}"'
    command = ['codesign', '--force', '--sign', fingerprint if release else '-']
    if release:
        command += ['--timestamp=none', '--requirements', '=designated => ' + requirement]
    # Do not use --deep while signing: Sparkle helpers retain their vendor signatures.
    subprocess.run(command + [str(app)], check=True)
    verification = ['codesign', '--verify', '--deep', '--strict']
    if release:
        verification += ['-R', '=' + requirement]
    subprocess.run(verification + [str(app)], check=True)
    print('Signed with persistent Kestrel identity' if release else 'Signed ad-hoc for local development')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('--release', action='store_true', help='Require pinned maintainer certificate')
    args = parser.parse_args()
    try:
        sign_app(args.app, args.release)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f'App signing failed: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
