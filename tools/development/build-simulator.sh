#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
BUILD_XCCONFIG_PATH="$DIST_DIR/Reynard-Simulator.xcconfig"
DERIVED_DATA="$DIST_DIR/simulator"
APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/Reynard.app"

mkdir -p "$DIST_DIR"
cp "$ROOT_DIR/browser/Configuration/Reynard.xcconfig" "$BUILD_XCCONFIG_PATH"
BUILD_SHA="$(git -C "$ROOT_DIR" rev-parse --short HEAD)"
printf '\nGECKO_DIST = $(SRCROOT)/../engine/firefox/obj-aarch64-apple-ios-sim/dist\nCURRENT_BUILD = %s\n' "$BUILD_SHA" >> "$BUILD_XCCONFIG_PATH"

xcodebuild build \
	-project "$ROOT_DIR/browser/Reynard.xcodeproj" \
	-scheme Reynard \
	-configuration Debug \
	-sdk iphonesimulator \
	-destination 'generic/platform=iOS Simulator' \
	-derivedDataPath "$DERIVED_DATA" \
	-xcconfig "$BUILD_XCCONFIG_PATH" \
	CODE_SIGNING_ALLOWED=NO \
	CODE_SIGNING_REQUIRED=NO

test -d "$APP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$DIST_DIR/Reynard-Simulator.zip"
