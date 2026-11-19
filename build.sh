#!/bin/sh
# Builds a universal (Apple Silicon + Intel) build/FingerStick.app.
#   ./build.sh          build only
#   ./build.sh --open   build and launch
#   ./build.sh --zip    also make build/FingerStick-<version>.zip for a GitHub release
set -e
cd "$(dirname "$0")"
APP=build/FingerStick.app
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target "$arch-apple-macos12" main.swift -o "build/FingerStick-$arch"
done
lipo -create build/FingerStick-arm64 build/FingerStick-x86_64 -o "$APP/Contents/MacOS/FingerStick"
rm build/FingerStick-arm64 build/FingerStick-x86_64
codesign --force --sign - "$APP"   # ad-hoc: runs locally; Gatekeeper warns on downloads (the Homebrew cask clears that)
codesign --verify --strict "$APP"
echo "built $APP $VERSION ($(lipo -archs "$APP/Contents/MacOS/FingerStick"))"
case "$1" in
  --open) open "$APP" ;;
  --zip)  ditto -c -k --keepParent "$APP" "build/FingerStick-$VERSION.zip" && echo "zipped build/FingerStick-$VERSION.zip" ;;
esac
