#!/usr/bin/env bash
# Builds installable artefacts: a .dmg for macOS and an unsigned .ipa for iPad.
#
#   ./scripts/package.sh          both
#   ./scripts/package.sh --mac    macOS only
#   ./scripts/package.sh --ios    iPad only
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
APP="$ROOT/VigilApp"
DIST="$ROOT/dist"
BUILD="$ROOT/.build/package"

command -v xcodegen >/dev/null || { echo "xcodegen not found: brew install xcodegen"; exit 1; }

what="${1:-all}"
mkdir -p "$DIST" "$BUILD"
(cd "$APP" && xcodegen generate --quiet)

build_mac() {
  echo "==> macOS"
  rm -rf "$BUILD/mac"
  xcodebuild -project "$APP/Vigil.xcodeproj" -scheme Vigil \
    -configuration Release -destination 'generic/platform=macOS' \
    -derivedDataPath "$BUILD/mac" build > "$BUILD/mac.log" 2>&1 \
    || { tail -30 "$BUILD/mac.log"; exit 1; }

  local built="$BUILD/mac/Build/Products/Release/Vigil.app"
  local stage="$BUILD/dmg"
  rm -rf "$stage"; mkdir -p "$stage"
  cp -R "$built" "$stage/"
  ln -s /Applications "$stage/Applications"

  rm -f "$DIST/Vigil.dmg"
  hdiutil create -volname Vigil -srcfolder "$stage" -ov -format UDZO \
    "$DIST/Vigil.dmg" > /dev/null
  echo "    $DIST/Vigil.dmg  ($(du -h "$DIST/Vigil.dmg" | cut -f1))"
}

build_ios() {
  echo "==> iPad"
  rm -rf "$BUILD/ios"
  # Unsigned on purpose: Sideloadly and AltStore re-sign with your own account.
  xcodebuild -project "$APP/Vigil.xcodeproj" -scheme Vigil \
    -configuration Release -destination 'generic/platform=iOS' \
    -derivedDataPath "$BUILD/ios" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build > "$BUILD/ios.log" 2>&1 \
    || { tail -30 "$BUILD/ios.log"; exit 1; }

  local built="$BUILD/ios/Build/Products/Release-iphoneos/Vigil.app"
  local stage="$BUILD/ipa"
  rm -rf "$stage"; mkdir -p "$stage/Payload"
  cp -R "$built" "$stage/Payload/"

  rm -f "$DIST/Vigil.ipa"
  (cd "$stage" && zip -qry "$DIST/Vigil.ipa" Payload)
  echo "    $DIST/Vigil.ipa  ($(du -h "$DIST/Vigil.ipa" | cut -f1))"
}

case "$what" in
  --mac) build_mac ;;
  --ios) build_ios ;;
  all|"") build_mac; build_ios ;;
  *) echo "usage: $0 [--mac|--ios]"; exit 1 ;;
esac

cat <<'NOTE'

macOS: open the .dmg and drag Vigil to Applications. The build is ad-hoc signed, so the
first launch needs right-click > Open, or:
    xattr -dr com.apple.quarantine /Applications/Vigil.app

iPad: the .ipa is unsigned. Install it with Sideloadly or AltStore, which sign it with your
own Apple ID. A free account expires after 7 days and needs a refresh.
NOTE
