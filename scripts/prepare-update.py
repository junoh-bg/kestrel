#!/usr/bin/env python3
"""Prepare a signed update feed locally. Never upload or alter a published feed."""
import argparse
import html
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
from release_metadata import ROOT, UPDATE_POLICY, load_metadata

ACCOUNT = 'junoh-bg.kestrel'


def validate_archive(path, metadata):
    expected_name = f"Kestrel-{metadata['version']}-macos-arm64.zip"
    if path.name != expected_name:
        raise ValueError(f'Expected archive named {expected_name}')
    with zipfile.ZipFile(path) as archive:
        manifests = [name for name in archive.namelist()
                     if name.endswith('.app/Contents/Info.plist') and not name.startswith('__MACOSX/')
                     and '/Frameworks/' not in name]
        if manifests != ['Kestrel.app/Contents/Info.plist']:
            raise ValueError('Archive must contain exactly one top-level Kestrel.app')
        info = plistlib.loads(archive.read(manifests[0]))
    expected = dict(UPDATE_POLICY, CFBundleIdentifier='com.localpilot.launcher',
                    CFBundleShortVersionString=metadata['version'], CFBundleVersion=str(metadata['build']))
    for key, value in expected.items():
        if info.get(key) != value:
            raise ValueError(f'Archive metadata mismatch: {key}')


def verify_publishing_key(tool_dir):
    # Lookup-only mode prints the public key; it never creates or exports a secret.
    public_key = subprocess.check_output(
        [str(tool_dir / 'generate_keys'), '--account', ACCOUNT, '-p'], text=True).strip()
    if public_key != UPDATE_POLICY['SUPublicEDKey']:
        raise ValueError('Keychain public key does not match the app verification key')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path, help='Final tested release ZIP from scripts/release.sh')
    args = parser.parse_args()
    archive = args.archive.resolve()
    metadata = load_metadata()
    validate_archive(archive, metadata)
    tool_dir = ROOT / '.build/artifacts/sparkle/Sparkle/bin'
    if not (tool_dir / 'generate_appcast').is_file():
        raise ValueError('Build the package first to resolve the pinned Sparkle tools')
    verify_publishing_key(tool_dir)
    # Keep the original archive untouched and retain output for review. No secret export.
    output = Path(tempfile.mkdtemp(prefix='update-', dir=archive.parent))
    shutil.copy2(archive, output / archive.name)
    shutil.copy2(ROOT / 'docs/updates/appcast.xml', output / 'appcast.xml')
    notes = (ROOT / f"docs/releases/{metadata['version']}.md").read_text()
    (output / archive.with_suffix('.html').name).write_text('<pre>' + html.escape(notes) + '</pre>')
    prefix = f"https://github.com/junoh-bg/kestrel/releases/download/v{metadata['version']}/"
    subprocess.run([str(tool_dir / 'generate_appcast'), '--account', ACCOUNT,
                    '--maximum-deltas', '0', '--download-url-prefix', prefix,
                    '--embed-release-notes', '--link', 'https://github.com/junoh-bg/kestrel',
                    str(output)], check=True)
    subprocess.run([str(tool_dir / 'sign_update'), '--account', ACCOUNT,
                    '--verify', str(output / 'appcast.xml')], check=True)
    print(f"Prepared signed feed: {output / 'appcast.xml'}")
    print('Publish and verify the ZIP first. Then copy this feed byte-for-byte into docs/updates/appcast.xml.')


if __name__ == '__main__':
    main()
