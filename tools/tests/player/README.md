# Local video player UI regression tests

This UIKit host compiles the production `VideoPlayerViewController.swift` and
tests it on an iPhone Simulator. It does not replace testing the full browser's
Downloads list or Gecko download pipeline.

Cases cover MP4, a merged HLS MP4, MKV, VP9/Opus WebM, damaged input, and both
AVFoundation and VLC playback/seek/fullscreen/exit with position retained.
Fullscreen assertions check the surface fills the landscape window and the
button is hittable; screenshots use `XCUIScreen` to avoid rotated app cropping.

Prepare the official dependency and synthetic fixtures (requires `ffmpeg`):

```sh
sh tools/development/prepare-player.sh --simulator
sh tools/tests/player/prepare-fixtures.sh /absolute/path/to/downloaded-hls.mp4
```

The optional HLS argument tests an actual browser download. If omitted, FFmpeg
generates a local HLS VOD and remuxes it for the player test.

Run against a booted simulator:

```sh
xcodebuild test -project tools/tests/player/PlayerTests.xcodeproj \
  -scheme PlayerTests -destination 'platform=iOS Simulator,id=<UDID>' \
  -parallel-testing-enabled NO -derivedDataPath dist/player-ui \
  -resultBundlePath dist/player-ui.xcresult CODE_SIGNING_ALLOWED=NO
```
