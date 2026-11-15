"""Build a reproducible offline ZIP for the selected Orbit appearance preview.

Run from any directory. Requires Python 3.10+; no Node or Swift dependency.
"""
import hashlib
import json
import re
import subprocess
import sys
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
WEB = ROOT / 'web'
VERSION = json.loads((WEB / 'package.json').read_text())['version']
if not re.fullmatch(r'\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?', VERSION):
    raise ValueError('Package version must be a semantic version')

subprocess.run([sys.executable, str(HERE / 'build-orbit-appearance.py')], check=True)
html = (WEB / 'public/orbit/index.html').read_bytes()
revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
dirty = bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True).strip())
manifest = {
    'name': 'Port Map — Workspace Orbit Preview',
    'version': VERSION,
    'sourceRevision': revision,
    'sourceDirty': dirty,
    'entryPoint': 'Port Map Orbit.html',
    'entryPointSha256': hashlib.sha256(html).hexdigest(),
    'appearance': {'light': 'Clay Studio', 'dark': 'After Hours', 'default': 'system'},
    'dataSource': 'Saved WhatCable report and manually entered connections',
    'liveHardwareAccess': False,
}
readme = f'''Port Map — Workspace Orbit Preview {VERSION}

GET STARTED ON YOUR MAC
1. Extract this ZIP (double-click it in Finder).
2. Double-click "Port Map Orbit.html".
3. Choose Light, Dark, or System at the top.

No installation, server, internet connection, Node, or Swift is required.
The HTML file contains its scripts, styles, and device imagery.

LIGHT: Clay Studio — warm terracotta/olive, compact peripherals, a larger Mac.
DARK: After Hours — plum/rose, with larger device portraits.
SYSTEM: follows your Mac/browser appearance unless you choose another mode.
The appearance preference is remembered when browser storage is available.

Click any device to trace its complete route. "Locate a device" selects without
hiding any images. "Trace only" emphasizes its cables. "Pause flow" stops motion.
All 19 image cards stay visible at typical desktop window sizes.

THIS IS A BROWSER PREVIEW, NOT A NATIVE MAC APP INSTALLER.
It displays a saved setup. It does not scan your Mac or report live traffic.
Animated paths illustrate signal/data direction. The same display name appears
on USB-C and HDMI; these are shown as separate reported paths, not confirmed
unique displays. Representative artwork is marked ~= (shown as ≈ in the UI),
and manually entered connections are marked M. See IMAGERY-NOTICES.txt.

Source and developer instructions:
https://github.com/afilen86/PortMap

To verify the HTML file, compare its SHA-256 with entryPointSha256 in release.json:
  shasum -a 256 "Port Map Orbit.html"
'''
notices = '''IMAGE AND DATA NOTICES

The package reuses the images already included in the PortMap repository:
- DeviceArtwork.png: existing device illustrations, including the Mac mini,
  controllers, monitors, drives, and Ethernet adapters.
- CalDigitHero.jpg and SatechiHero.jpg: product photography from Adorama listings
  cd500934 and satstgnmmes, as documented in the repository README.
- Scarlett4i4.jpg: Focusrite product photography.
- KlipschFives.jpg: Klipsch product photography.
- MaestroDMX.jpg: product photography from maestrodmx.com.

Product names, trademarks, and third-party images remain with their respective
owners. Inclusion does not grant additional rights to reuse their images.
The repository documents these images as used for this personal application.

Representative enclosure, screen, and adapter artwork is marked ≈ in the UI.
Manually entered connections follow Resources/ManualConnections.json and are
marked M. Hidden internal USB interfaces are condensed into dotted paths.
Topology and reported rates follow the saved overview-scan.json, not live scans.

The offline HTML uses system fonts and plain JavaScript. It does not bundle the
React/Vite development dependencies or require an external asset/CDN service.
'''
files = {
    'Port Map Orbit.html': html,
    'README.txt': readme.encode(),
    'IMAGERY-NOTICES.txt': notices.encode(),
    'release.json': (json.dumps(manifest, indent=2, ensure_ascii=False) + '\n').encode(),
}
folder = f'PortMap-Orbit-Preview-{VERSION}'
out = WEB / 'release'
out.mkdir(exist_ok=True)
archive = out / f'{folder}.zip'
with zipfile.ZipFile(archive, 'w') as package:
    for name, contents in sorted(files.items()):
        entry = zipfile.ZipInfo(f'{folder}/{name}', date_time=(1980, 1, 1, 0, 0, 0))
        entry.create_system = 3
        entry.external_attr = 0o100644 << 16
        package.writestr(entry, contents, compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
with zipfile.ZipFile(archive) as package:
    assert package.testzip() is None
checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
checksum_file = archive.with_suffix('.zip.sha256')
checksum_file.write_text(f'{checksum}  {archive.name}\n')
print(f'Packaged {archive} ({archive.stat().st_size:,} bytes)')
print(f'SHA-256 {checksum}')
print(f'Manifest source: {revision}{" (uncommitted changes)" if dirty else ""}')
