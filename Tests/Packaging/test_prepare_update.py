import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[2]


class PrepareUpdateTests(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location('prepare_update', ROOT / 'scripts/prepare-update.py')
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)

    def archive(self, directory, **overrides):
        info = dict(self.module.UPDATE_POLICY, CFBundleIdentifier='com.localpilot.launcher',
                    CFBundleShortVersionString='2.3.4', CFBundleVersion='42')
        info.update(overrides)
        path = Path(directory) / 'Kestrel-2.3.4-macos-arm64.zip'
        with zipfile.ZipFile(path, 'w') as archive:
            archive.writestr('Kestrel.app/Contents/Info.plist', plistlib.dumps(info))
        return path

    def test_validates_release_identity_before_signing(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = self.archive(directory)
            self.module.validate_archive(archive, {'version': '2.3.4', 'build': 42})
            for metadata in [{'version': '2.3.5', 'build': 42}, {'version': '2.3.4', 'build': 43}]:
                with self.assertRaises(ValueError):
                    self.module.validate_archive(archive, metadata)

    def test_rejects_wrong_identity_key_and_update_policy(self):
        with tempfile.TemporaryDirectory() as directory:
            for override in [{'CFBundleIdentifier': 'example.other'}, {'SUPublicEDKey': 'wrong'},
                             {'SURequireSignedFeed': False}, {'SUAllowsAutomaticUpdates': True}]:
                with self.subTest(override=override):
                    with self.assertRaises(ValueError):
                        self.module.validate_archive(self.archive(directory, **override), {'version': '2.3.4', 'build': 42})

    def test_rejects_multiple_apps(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = self.archive(directory)
            with zipfile.ZipFile(archive, 'a') as file:
                file.writestr('Another.app/Contents/Info.plist', b'not an app')
            with self.assertRaises(ValueError):
                self.module.validate_archive(archive, {'version': '2.3.4', 'build': 42})

    def test_rejects_a_different_keychain_signing_key(self):
        with patch.object(self.module.subprocess, 'check_output', return_value='wrong-key\n'):
            with self.assertRaises(ValueError):
                self.module.verify_publishing_key(Path('/tools'))
        with patch.object(self.module.subprocess, 'check_output', return_value=self.module.UPDATE_POLICY['SUPublicEDKey'] + '\n'):
            self.module.verify_publishing_key(Path('/tools'))
