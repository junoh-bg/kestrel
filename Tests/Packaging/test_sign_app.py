import os
import importlib.util
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'scripts/sign-app.py'


class AppSigningTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(SCRIPT.is_file(), 'App signing must have a reusable implementation')
        (ROOT / 'dist').mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(prefix='signing-test-', dir=ROOT / 'dist')
        self.addCleanup(self.temp.cleanup)
        self.app = Path(self.temp.name) / 'Kestrel.app'
        binary = self.app / 'Contents/MacOS/Kestrel'
        binary.parent.mkdir(parents=True)
        shutil.copyfile('/usr/bin/true', binary)
        binary.chmod(0o755)
        self.info_path = self.app / 'Contents/Info.plist'
        self.info = dict(CFBundleIdentifier='com.localpilot.launcher', CFBundleName='Kestrel',
                         CFBundleExecutable='Kestrel', CFBundlePackageType='APPL', CFBundleVersion='1')
        self.info_path.write_bytes(plistlib.dumps(self.info))

    def sign(self, *args):
        return subprocess.run(['python3', '-B', str(SCRIPT), str(self.app), *args],
                              capture_output=True, text=True)

    def test_source_build_remains_valid_ad_hoc(self):
        result = self.sign()
        self.assertEqual(result.returncode, 0, result.stderr)
        display = subprocess.run(['codesign', '-dv', str(self.app)], capture_output=True, text=True)
        self.assertIn('Signature=adhoc', display.stderr)
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(self.app)], check=True)

    def test_wrong_bundle_identity_is_rejected(self):
        self.info['CFBundleIdentifier'] = 'org.example.impostor'
        self.info_path.write_bytes(plistlib.dumps(self.info))
        result = self.sign('--release')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('bundle identifier', result.stderr)

    def test_missing_release_identity_fails_without_ad_hoc_fallback(self):
        spec = importlib.util.spec_from_file_location('sign_app', SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        fake_root = Path(self.temp.name) / 'policy'
        (fake_root / 'config').mkdir(parents=True)
        (fake_root / 'config/code-signing.json').write_text(json.dumps({
            'certificate_sha1': '0' * 40, 'bundle_identifier': 'com.localpilot.launcher'}))
        module.ROOT = fake_root
        # First establish an ad-hoc baseline. A missing release identity must
        # fail, never report this baseline as a successfully signed release.
        self.assertEqual(self.sign().returncode, 0)
        with self.assertRaises(subprocess.CalledProcessError):
            module.sign_app(self.app, release=True)

    @unittest.skipUnless(os.environ.get('KESTREL_TEST_RELEASE_SIGNING') == '1',
                         'Needs maintainer Keychain identity')
    def test_changed_build_preserves_requirement_and_rejects_ad_hoc(self):
        result = self.sign('--release')
        self.assertEqual(result.returncode, 0, result.stderr)
        first = subprocess.run(['codesign', '-d', '-r-', str(self.app)], capture_output=True, text=True)
        requirement = first.stdout.strip().removeprefix('designated => ')
        self.assertIn('certificate leaf', requirement)
        self.info['CFBundleVersion'] = '2'
        self.info_path.write_bytes(plistlib.dumps(self.info))
        result = self.sign('--release')
        self.assertEqual(result.returncode, 0, result.stderr)
        second = subprocess.run(['codesign', '-d', '-r-', str(self.app)], capture_output=True, text=True)
        self.assertEqual(first.stdout, second.stdout)
        subprocess.run(['codesign', '--verify', '--strict', '-R', '=' + requirement, str(self.app)], check=True)
        self.assertEqual(self.sign().returncode, 0)
        rejected = subprocess.run(['codesign', '--verify', '-R', '=' + requirement, str(self.app)],
                                  capture_output=True, text=True)
        self.assertNotEqual(rejected.returncode, 0)


if __name__ == '__main__':
    unittest.main()
