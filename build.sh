#!/bin/zsh
# Builds "Port Map.app" from port-map-source/ into build/.
#
#   ./build.sh            build the app
#   ./build.sh --run      build, then open it
#   ./build.sh --zip      build, then zip it as build/PortMap-<version>.zip
#   ./build.sh --debug    unoptimized build (faster compile, better crash logs)
#
# Version numbers come from port-map-source/Info.plist
# (CFBundleShortVersionString = version, CFBundleVersion = build).

set -euo pipefail

ROOT="${0:A:h}"
SRC="$ROOT/port-map-source"
OUT="$ROOT/build"
APP="$OUT/Port Map.app"

run=0; zip=0; opt="-O"
for arg in "$@"; do
  case "$arg" in
    --run) run=1 ;;
    --zip) zip=1 ;;
    --debug) opt="-Onone -g" ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SRC/Info.plist")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$SRC/Info.plist")
echo "Building Port Map $version (build $build)…"

mkdir -p "$OUT"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc ${=opt} -parse-as-library \
  -target arm64-apple-macos14.0 \
  -module-cache-path "$OUT/module-cache" \
  "$SRC"/*.swift \
  -o "$APP/Contents/MacOS/PortMap"

cp "$SRC/Info.plist" "$APP/Contents/Info.plist"
cp "$SRC/Resources/"* "$APP/Contents/Resources/"

# Ad-hoc signature so macOS will launch it locally. Extended attributes
# (Finder info, quarantine) on copied files make codesign refuse the bundle.
xattr -cr "$APP"
if ! sign_output=$(codesign --force --sign - "$APP" 2>&1); then
  echo "$sign_output" >&2
  exit 1
fi
codesign --verify "$APP"

echo "Built: $APP"

if (( zip )); then
  archive="$OUT/PortMap-$version-build$build.zip"
  rm -f "$archive"
  ditto -c -k --keepParent "$APP" "$archive"
  echo "Zipped: $archive"
fi

if (( run )); then
  open "$APP"
fi
