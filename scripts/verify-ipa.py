#!/usr/bin/env python3
import pathlib, plistlib, struct, sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
    assert z.testzip() is None
    info = plistlib.loads(z.read('Payload/Folio.app/Info.plist'))
    assert info['CFBundleIdentifier'] == 'com.folio.reader'
    assert info['CFBundleSupportedPlatforms'] == ['iPhoneOS']
    assert info['MinimumOSVersion'] == '17.0'
    data = z.read('Payload/Folio.app/' + info['CFBundleExecutable'])
    # Thin arm64 Mach-O; the app verifier checks fat binaries with lipo.
    if data[:4] == b'\xcf\xfa\xed\xfe':
        assert struct.unpack_from('<I', data, 4)[0] == 0x0100000c
        commands = struct.unpack_from('<I', data, 16)[0]
        offset, device_platform = 32, False
        for _ in range(commands):
            command, size = struct.unpack_from('<II', data, offset)
            assert size >= 8 and offset + size <= len(data), 'Invalid Mach-O command'
            if command == 0x32:  # LC_BUILD_VERSION: IOS=2, IOSSIMULATOR=7
                platform, minimum = struct.unpack_from('<II', data, offset + 8)
                assert platform == 2, 'Executable is not built for physical iOS'
                assert minimum == (17 << 16), 'Unexpected executable deployment target'
                device_platform = True
            offset += size
        assert device_platform, 'Missing device platform load command'
    else:
        assert data[:4] in (b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'), 'Invalid Mach-O'
    assert 'Payload/Folio.app/Assets.car' in z.namelist()
print('IPA structure, device platform and executable verified:', pathlib.Path(sys.argv[1]).resolve())
