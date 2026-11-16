import pathlib, plistlib, subprocess, sys, tempfile, unittest, zipfile
ROOT = pathlib.Path(__file__).resolve().parents[1]
class PackagingTests(unittest.TestCase):
    def test_reject_simulator_ipa(self):
        with tempfile.TemporaryDirectory() as tmp:
            ipa = pathlib.Path(tmp) / 'fake.ipa'
            with zipfile.ZipFile(ipa, 'w') as z:
                z.writestr('Payload/Folio.app/Info.plist', plistlib.dumps({'CFBundleIdentifier':'com.folio.reader','CFBundleSupportedPlatforms':['iPhoneSimulator'],'MinimumOSVersion':'17.0'}))
            result = subprocess.run([sys.executable, str(ROOT/'scripts/verify-ipa.py'), str(ipa)], capture_output=True)
            self.assertNotEqual(result.returncode, 0)
    def test_reject_missing_executable(self):
        with tempfile.TemporaryDirectory() as tmp:
            ipa = pathlib.Path(tmp) / 'fake.ipa'
            with zipfile.ZipFile(ipa, 'w') as z:
                z.writestr('Payload/Folio.app/Info.plist', plistlib.dumps({'CFBundleIdentifier':'com.folio.reader','CFBundleSupportedPlatforms':['iPhoneOS'],'MinimumOSVersion':'17.0','CFBundleExecutable':'Folio'}))
            self.assertNotEqual(subprocess.run([sys.executable, str(ROOT/'scripts/verify-ipa.py'), str(ipa)], capture_output=True).returncode, 0)
    def test_device_build_configuration(self):
        script = (ROOT/'scripts/build-ipa.sh').read_text()
        self.assertIn('-sdk iphoneos', script)
        self.assertIn('generic/platform=iOS', script)
        self.assertIn('verify-app.py', script)
        self.assertIn('verify-ipa.py', script)
    def test_all_app_icons_are_present(self):
        import json
        folder = ROOT/'Folio/Assets.xcassets/AppIcon.appiconset'
        for icon in json.loads((folder/'Contents.json').read_text())['images']:
            self.assertTrue((folder/icon['filename']).is_file())
if __name__ == '__main__': unittest.main()
