"""Build the bundled WKWebView UI; keep the offline preview unchanged."""
import base64
import importlib.util
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('orbit_appearance', HERE / 'build-orbit-appearance.py')
appearance = importlib.util.module_from_spec(spec)
spec.loader.exec_module(appearance)
root = appearance.studies.library.ROOT
page = appearance.page
asset = 'data:image/png;base64,' + base64.b64encode((root / 'port-map-source/Resources/TwisterArtwork.png').read_bytes()).decode()
# Plain inline JavaScript avoids file-URL module-loading restrictions in WebKit.
bridge = (root / 'web/native/orbit-host.js').read_text()
bridge = 'DATA.assets.twister=' + json.dumps(asset) + ';\n' + bridge
assert page.count('applyAppearance(appearance);document.fonts.ready.then(fit);') == 1
page = page.replace('applyAppearance(appearance);document.fonts.ready.then(fit);', bridge + '\napplyAppearance(appearance);document.fonts.ready.then(fit);\nstartNativeHost();')
out = root / 'web/native/dist/index.html'
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(page)
print(f'Built native Orbit UI: {out} ({out.stat().st_size:,} bytes)')
