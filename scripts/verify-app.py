#!/usr/bin/env python3
import pathlib, plistlib, subprocess, sys
app = pathlib.Path(sys.argv[1])
info = plistlib.loads((app / 'Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == 'com.folio.reader'
assert info['MinimumOSVersion'] == '17.0'
assert info['CFBundleSupportedPlatforms'] == ['iPhoneOS'], 'Simulator app rejected'
exe = app / info['CFBundleExecutable']
assert 'arm64' in subprocess.check_output(['lipo', '-archs', str(exe)], text=True)
assert (app / 'Assets.car').is_file(), 'Missing compiled assets'
assert info.get('CFBundleIcons'), 'Missing app icons'
for binary in (app / 'Frameworks').glob('*.framework'):
    assert 'arm64' in subprocess.check_output(['lipo', '-archs', str(binary / binary.stem)], text=True)
load = subprocess.check_output(['otool', '-L', str(exe)], text=True)
for line in load.splitlines()[1:]:
    dep = line.strip().split(' (')[0]
    if dep.startswith('@rpath/'):
        assert (app / 'Frameworks' / dep.removeprefix('@rpath/')).exists(), dep
    else:
        assert dep.startswith(('/System/Library/', '/usr/lib/')), dep
print(load)
sign = subprocess.run(['codesign', '-dv', str(app)], capture_output=True, text=True)
print('Signing state:', sign.stderr.strip())
print('Device app verified: arm64, iPhoneOS, bundle ID, minimum OS, icons, dependencies.')
