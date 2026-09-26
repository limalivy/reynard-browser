#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
DERIVED_DATA="$DIST_DIR/simulator"
APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/Reynard.app"

mkdir -p "$DIST_DIR"

xcodebuild build \
	-project "$ROOT_DIR/browser/Reynard.xcodeproj" \
	-scheme Reynard \
	-configuration Debug \
	-sdk iphonesimulator \
	-destination 'generic/platform=iOS Simulator' \
	-arch arm64 \
	-derivedDataPath "$DERIVED_DATA" \
	-xcconfig "$ROOT_DIR/browser/Configuration/Reynard.xcconfig" \
	GECKO_DIST="$ROOT_DIR/engine/firefox/obj-aarch64-apple-ios-sim/dist" \
	CURRENT_BUILD="$(git -C "$ROOT_DIR" rev-parse --short HEAD)" \
	CODE_SIGNING_ALLOWED=NO \
	CODE_SIGNING_REQUIRED=NO

test -d "$APP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$DIST_DIR/Reynard-Simulator.zip"
