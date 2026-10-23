import importlib.util
import json
import plistlib
import struct
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[2] / 'scripts'
sys.path.insert(0, str(SCRIPTS))
from verify_ipa import inspect_ipa
spec = importlib.util.spec_from_file_location('update_source', SCRIPTS / 'update-source.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class DistributionTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        self.ipa = self.root / 'Remio.ipa'
        self.source = self.root / 'source.json'

    def tearDown(self):
        self.directory.cleanup()

    def fixture(self, version='0.1.0', platform=2, extras=None):
        info = dict(CFBundleIdentifier='com.remio.app', CFBundleExecutable='Remio',
                    CFBundleShortVersionString=version, CFBundleVersion='1',
                    CFBundleSupportedPlatforms=['iPhoneOS'], MinimumOSVersion='26.0',
                    NSLocalNetworkUsageDescription='Conectar con el Portal')
        binary = struct.pack('<8I', 0xFEEDFACF, 0x0100000C, 0, 2, 1, 24, 0, 0)
        binary += struct.pack('<6I', 0x32, 24, platform, 0, 0, 0)
        with zipfile.ZipFile(self.ipa, 'w') as archive:
            archive.writestr('Payload/Remio.app/Info.plist', plistlib.dumps(info))
            archive.writestr('Payload/Remio.app/Remio', binary)
            archive.writestr('Payload/Remio.app/AppIcon60x60@2x.png', b'icon')
            for name, data in (extras or {}).items():
                archive.writestr(name, data)

    def test_metadata_comes_from_binary_and_previous_versions_are_kept(self):
        self.fixture()
        module.update_source(self.ipa, self.source, 'AnubisReal/Remio', 'v0.1.0')
        self.fixture('0.2.0')
        module.update_source(self.ipa, self.source, 'AnubisReal/Remio', 'v0.2.0')
        app = json.loads(self.source.read_text())['apps'][0]
        self.assertEqual([v['version'] for v in app['versions']], ['0.2.0', '0.1.0'])
        self.assertEqual(app['versions'][0]['size'], self.ipa.stat().st_size)
        self.assertEqual(app['versions'][0]['minOSVersion'], '26.0')
        self.assertEqual(app['appPermissions']['privacy'], {'NSLocalNetworkUsageDescription': 'Conectar con el Portal'})
        self.assertNotIn('marketplaceID', app)

    def test_older_release_does_not_replace_latest(self):
        self.fixture('0.2.0')
        module.update_source(self.ipa, self.source, 'AnubisReal/Remio', 'v0.2.0')
        self.fixture('0.1.0')
        module.update_source(self.ipa, self.source, 'AnubisReal/Remio', 'v0.1.0')
        self.assertEqual(json.loads(self.source.read_text())['apps'][0]['versions'][0]['version'], '0.2.0')

    def test_republishing_does_not_duplicate_versions(self):
        self.fixture()
        for _ in range(2):
            module.update_source(self.ipa, self.source, 'AnubisReal/Remio', 'v0.1.0')
        self.assertEqual(len(json.loads(self.source.read_text())['apps'][0]['versions']), 1)

    def test_rejects_simulator_binary(self):
        self.fixture(platform=7)
        with self.assertRaises(ValueError):
            inspect_ipa(self.ipa)

    def test_rejects_private_signing_material(self):
        self.fixture(extras={'Payload/Remio.app/embedded.mobileprovision': b'private'})
        with self.assertRaises(ValueError):
            inspect_ipa(self.ipa)

    def test_rejects_tag_version_mismatch(self):
        self.fixture()
        with self.assertRaises(ValueError):
            module.update_source(self.ipa, self.source, 'AnubisReal/Remio', 'v1.0.0')
        self.assertFalse(self.source.exists())


if __name__ == '__main__':
    unittest.main()
