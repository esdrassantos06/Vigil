#!/usr/bin/env bash
# Compiles and opens Vigil. Requires Xcode and xcodegen (brew install xcodegen).
set -euo pipefail

cd "$(dirname "$0")/../VigilApp"

command -v xcodegen >/dev/null || { echo "xcodegen Missing: brew install xcodegen"; exit 1; }

xcodegen
xcodebuild -project Vigil.xcodeproj -scheme Vigil \
  -destination 'platform=macOS' -configuration Debug build

APP=$(find ~/Library/Developer/Xcode/DerivedData -name Vigil.app -path '*Debug*' -maxdepth 5 | head -1)
echo "$APP built successfully"
[ "${1:-}" = "--open" ] && open "$APP"
