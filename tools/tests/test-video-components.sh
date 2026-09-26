#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
DEVICE=${1:?Pass a booted Simulator UDID}
FIXTURES=${2:?Pass the absolute fixture directory}
OUT="$ROOT/dist/video-component-tests"
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
cd "$ROOT"
sh tools/development/build-media.sh --simulator
mkdir -p "$OUT/sim-module" "$OUT/module-cache"
swiftc -module-cache-path "$OUT/module-cache" browser/Reynard/Client/Stores/HLSPlaylist.swift \
    tools/tests/HLSPlaylistTests.swift -o "$OUT/hls-tests"
"$OUT/hls-tests"
xcrun swiftc -target arm64-apple-ios13.0-simulator -sdk "$SDK" -module-cache-path "$OUT/module-cache" \
    -emit-module -emit-library -static -module-name GeckoView tools/tests/VideoTransportStub.swift \
    -emit-module-path "$OUT/sim-module/GeckoView.swiftmodule" -o "$OUT/sim-module/libGeckoView.a"
xcrun clang -target arm64-apple-ios13.0-simulator -isysroot "$SDK" -Ibrowser/Reynard/Bridging \
    -Isupport/media/build/iphonesimulator/include -c browser/Reynard/Client/Stores/VideoRemux.c -o "$OUT/VideoRemux.o"
xcrun swiftc -target arm64-apple-ios13.0-simulator -sdk "$SDK" -module-cache-path "$OUT/module-cache" \
    -I "$OUT/sim-module" -L "$OUT/sim-module" -lGeckoView \
    -import-objc-header browser/Reynard/Bridging/VideoRemux.h \
    browser/Reynard/Client/Stores/HLSPlaylist.swift browser/Reynard/Client/Stores/VideoDownloadTask.swift \
    tools/tests/VideoPipelineTests.swift "$OUT/VideoRemux.o" \
    -Lsupport/media/build/iphonesimulator/lib -lavformat -lavcodec -lavutil -o "$OUT/video-pipeline-simulator"
xcrun simctl spawn "$DEVICE" "$OUT/video-pipeline-simulator" "$FIXTURES" "$OUT/pipeline"
