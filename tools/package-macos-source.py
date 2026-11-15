"""Make a portable source build kit; does not claim to build a Mac binary."""
from pathlib import Path
import hashlib
import plistlib
import zipfile

ROOT = Path(__file__).resolve().parents[1]
version = plistlib.loads((ROOT / 'port-map-source/Info.plist').read_bytes())['CFBundleShortVersionString']
prefix = f'PortMap-Mac-Build-Kit-{version}'
out = ROOT / 'macos-build-kit'
out.mkdir(exist_ok=True)
files = [ROOT / name for name in ['build.sh', 'Build Port Map.command', 'MACOS.md']]
files += sorted(p for p in (ROOT / 'port-map-source').rglob('*') if p.is_file())
files += [ROOT / 'web/design-tools' / name for name in [
    'build-mockups.py', 'build-orbit-variants.py', 'build-orbit-appearance.py',
    'build-native-orbit.py', 'mockups.template.html', 'orbit-variants.css']]
files += [ROOT / 'web/native/orbit-host.js']
archive = out / f'{prefix}.zip'
with zipfile.ZipFile(archive, 'w') as z:
    for path in files:
        info = zipfile.ZipInfo(f'{prefix}/{path.relative_to(ROOT)}', date_time=(1980, 1, 1, 0, 0, 0))
        info.create_system = 3
        info.external_attr = (0o100755 if path.name in ['build.sh', 'Build Port Map.command'] else 0o100644) << 16
        z.writestr(info, path.read_bytes(), compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
    z.writestr(f'{prefix}/START-HERE.txt',
        'This is a source build kit, not a prebuilt application.\n'
        'On your Mac, open MACOS.md, then double-click Build Port Map.command.\n'
        'Requires macOS 14+, Xcode Command Line Tools, and Python 3.\n'
        'The build creates and opens build/Port Map.app.\n')
checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
archive.with_suffix('.zip.sha256').write_text(f'{checksum}  {archive.name}\n')
print(f'Mac source kit: {archive} ({archive.stat().st_size:,} bytes)\nSHA-256: {checksum}')
