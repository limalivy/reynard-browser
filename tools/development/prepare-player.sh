#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
BASE="$ROOT/support/vlckit"
VERSION=3.7.2
SHA256=77b867667e5e62aa4062e71b7a4f76a0e2f505425916091c0eb0f94d9ad4af80
URL=https://download.videolan.org/pub/cocoapods/prod/MobileVLCKit-3.7.2-3e42ae47-79128878.tar.xz
SDK=iphoneos
SLICE=ios-arm64_armv7_armv7s
if [ "${1:-}" = "--simulator" ]; then
    SDK=iphonesimulator
    SLICE=ios-arm64_i386_x86_64-simulator
fi
ARCHIVE="$BASE/archives/MobileVLCKit-$VERSION.tar.xz"
SOURCE="$BASE/source/MobileVLCKit-binary"
OUTPUT="$BASE/build/$SDK/MobileVLCKit.framework"
STAMP="$VERSION-$(shasum -a 256 "$0" | cut -d ' ' -f 1)"
if [ -f "$BASE/build/$SDK/stamp" ] && [ "$(cat "$BASE/build/$SDK/stamp")" = "$STAMP" ]; then exit 0; fi
mkdir -p "$BASE/archives" "$BASE/source" "$BASE/build/$SDK"
if [ ! -f "$ARCHIVE" ]; then
    curl --http1.1 --fail --location --retry 3 "$URL" -o "$ARCHIVE.download"
    printf '%s  %s\n' "$SHA256" "$ARCHIVE.download" | shasum -a 256 -c -
    mv "$ARCHIVE.download" "$ARCHIVE"
fi
printf '%s  %s\n' "$SHA256" "$ARCHIVE" | shasum -a 256 -c -
if [ ! -d "$SOURCE/MobileVLCKit.xcframework" ]; then
    tar -xJf "$ARCHIVE" -C "$BASE/source" --exclude='*/dSYMs/*' --exclude='*/doc/*' --exclude='*/Sample Code/*'
fi
ditto "$SOURCE/MobileVLCKit.xcframework/$SLICE/MobileVLCKit.framework" "$OUTPUT"
xcrun lipo "$OUTPUT/MobileVLCKit" -thin arm64 -output "$BASE/build/$SDK/MobileVLCKit-arm64"
mv "$BASE/build/$SDK/MobileVLCKit-arm64" "$OUTPUT/MobileVLCKit"
xcrun bitcode_strip "$OUTPUT/MobileVLCKit" -r -o "$OUTPUT/MobileVLCKit"
codesign --force --sign - "$OUTPUT"
printf '%s' "$STAMP" > "$BASE/build/$SDK/stamp"
