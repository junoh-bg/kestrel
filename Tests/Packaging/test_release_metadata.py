import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ReleaseMetadataTests(unittest.TestCase):
    def setUp(self):
        path = ROOT / 'scripts/release_metadata.py'
        self.assertTrue(path.exists(), 'Release metadata must have a shared implementation')
        spec = importlib.util.spec_from_file_location('release_metadata', path)
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)

    def test_bundle_uses_release_version_and_preserves_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            metadata = root / 'version.json'
            metadata.write_text(json.dumps({'version': '2.3.4', 'build': 42}))
            value = self.module.load_metadata(metadata)
            output = root / 'Info.plist'
            self.module.write_info(output, value)
            info = plistlib.loads(output.read_bytes())
            self.assertEqual(info['CFBundleShortVersionString'], '2.3.4')
            self.assertEqual(info['CFBundleVersion'], '42')
            self.assertEqual(info['CFBundleIdentifier'], 'com.localpilot.launcher')
            self.assertEqual(info['LSMinimumSystemVersion'], '14.0')

    def test_rejects_invalid_versions_and_builds(self):
        invalid = [('1.2', 1), ('01.2.3', 1), ('1.2.3-beta', 1),
                   ('1.2.3', 0), ('1.2.3', True), ('1.2.3', '9')]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'version.json'
            for version, build in invalid:
                with self.subTest(version=version, build=build):
                    path.write_text(json.dumps({'version': version, 'build': build}))
                    with self.assertRaises(ValueError):
                        self.module.load_metadata(path)

    def test_current_release_has_notes_and_changelog(self):
        metadata = self.module.load_metadata(ROOT / 'version.json')
        version = metadata['version']
        self.assertTrue((ROOT / 'docs/releases' / (version + '.md')).is_file())
        self.assertIn('## [' + version + ']', (ROOT / 'CHANGELOG.md').read_text())


if __name__ == '__main__':
    unittest.main()
