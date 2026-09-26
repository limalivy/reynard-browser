#!/bin/sh

# Only demuxing/remuxing is needed. No external codecs, GPL components or network.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
VERSION=8.1.3
SHA256=7138d28c96d9d3e3af4ee3d8cad72741f8ffb40da90c1112235dea3ecd3178a3
SDK=iphoneos
TARGET=arm64-apple-ios13.0
if [ "${1:-}" = "--simulator" ]; then
    SDK=iphonesimulator
    TARGET=arm64-apple-ios13.0-simulator
fi
BASE="$ROOT/support/media"
ARCHIVE="$BASE/archives/ffmpeg-$VERSION.tar.xz"
SOURCE="$BASE/source/ffmpeg-$VERSION"
OUTPUT="$BASE/build/$SDK"
STAMP="$VERSION-$(shasum -a 256 "$0" | cut -d ' ' -f 1)-$(xcodebuild -version | tr '\n' ' ')"
if [ -f "$OUTPUT/stamp" ] && [ "$(cat "$OUTPUT/stamp")" = "$STAMP" ]; then
    exit 0
fi
mkdir -p "$BASE/archives" "$BASE/source" "$OUTPUT/objects"
if [ ! -f "$ARCHIVE" ]; then
    curl --fail --location --retry 3 "https://ffmpeg.org/releases/ffmpeg-$VERSION.tar.xz" -o "$ARCHIVE"
fi
printf '%s  %s\n' "$SHA256" "$ARCHIVE" | shasum -a 256 -c -
if [ ! -f "$SOURCE/configure" ]; then
    tar -xf "$ARCHIVE" -C "$BASE/source"
fi
cd "$OUTPUT/objects"
"$SOURCE/configure" \
    --prefix="$OUTPUT" --cc="$(xcrun --sdk "$SDK" -f clang)" \
    --arch=aarch64 --target-os=darwin --enable-cross-compile \
    --sysroot="$(xcrun --sdk "$SDK" --show-sdk-path)" \
    --extra-cflags="-target $TARGET -fPIC" --extra-ldflags="-target $TARGET" \
    --disable-autodetect --disable-everything --disable-programs --disable-doc \
    --disable-debug --disable-network --disable-avdevice --disable-avfilter \
    --disable-swscale --disable-swresample --disable-shared --enable-static \
    --enable-small --enable-demuxer=hls,mpegts,mov,aac,matroska \
    --enable-muxer=mp4 --enable-protocol=file,crypto \
    --enable-parser=aac,h264,hevc --enable-decoder=aac,h264,hevc \
    --enable-bsf=aac_adtstoasc,extract_extradata
make -j "$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
make install
printf '%s' "$STAMP" > "$OUTPUT/stamp"
