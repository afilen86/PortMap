#!/bin/bash
# Build Port Map.app with the locally bundled Workspace Orbit UI.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$ROOT/port-map-source"
OUT="$ROOT/build"
APP="$OUT/Port Map.app"
run=0; zip=0; smoke=0; universal=0
swift_flags=(-O)
for arg in "$@"; do
  case "$arg" in
    --run) run=1 ;;
    --zip) zip=1 ;;
    --debug) swift_flags=(-Onone -g) ;;
    --universal) universal=1 ;;
    --smoke-test) smoke=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'Building the Mac app requires macOS 14+ and Xcode Command Line Tools.' >&2
  exit 1
fi
if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo 'Install Xcode Command Line Tools with: xcode-select --install' >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo 'Python 3.10+ is needed to bundle the Orbit interface.' >&2
  exit 1
fi
python3 "$ROOT/web/design-tools/build-native-orbit.py"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SRC/Info.plist")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$SRC/Info.plist")
echo "Building Port Map $version (build $build)…"
mkdir -p "$OUT"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Orbit"
architectures=("$(uname -m)")
if (( universal )); then architectures=(arm64 x86_64); fi
binaries=()
for architecture in "${architectures[@]}"; do
  binary="$OUT/PortMap-$architecture"
  xcrun swiftc "${swift_flags[@]}" -swift-version 5 -parse-as-library \
    -target "$architecture-apple-macos14.0" \
    -module-cache-path "$OUT/module-cache" \
    "$SRC"/*.swift -o "$binary"
  binaries+=("$binary")
done
if (( universal )); then
  xcrun lipo -create "${binaries[@]}" -output "$APP/Contents/MacOS/PortMap"
else
  cp "${binaries[0]}" "$APP/Contents/MacOS/PortMap"
fi
cp "$SRC/Info.plist" "$APP/Contents/Info.plist"
cp "$SRC/Resources/"* "$APP/Contents/Resources/"
cp "$ROOT/web/native/dist/index.html" "$APP/Contents/Resources/Orbit/index.html"
xattr -cr "$APP"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "Built: $APP"
if (( smoke )); then
  python3 - "$APP/Contents/MacOS/PortMap" <<'PY'
import subprocess, sys
subprocess.run([sys.argv[1], '--demo', '--smoke-test'], timeout=45, check=True)
PY
fi
if (( zip )); then
  archive="$OUT/PortMap-$version-build$build.zip"
  rm -f "$archive"
  ditto -c -k --keepParent "$APP" "$archive"
  echo "Zipped: $archive"
fi
if (( run )); then open "$APP"; fi
