#!/bin/bash
# Double-click this file in Finder on your Mac.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo 'Install the free Xcode Command Line Tools, then run this file again:'
  echo '  xcode-select --install'
  read -r -p 'Press Return to close…' _unused
  exit 1
fi
if ! bash ./build.sh --zip --run; then
  echo 'Build failed. The error is printed above.'
  read -r -p 'Press Return to close…' _unused
  exit 1
fi
echo 'Port Map is running. The app and ZIP are in the build folder.'
open "$ROOT/build"
read -r -p 'Press Return to close…' _unused
