# Compatible local video playback

The player uses AVFoundation for supported files and MobileVLCKit for containers
such as MKV/WebM/AVI or when the system decoder rejects the file. The controls and
fullscreen presentation are implemented in Reynard.

`tools/development/prepare-player.sh` downloads the official VideoLAN 3.7.2
XCFramework, checks a pinned SHA-256, selects the device or simulator slice and
keeps only arm64. `--simulator` selects the arm64 iOS Simulator framework.
The dependency remains a separate dynamic framework; its LGPL 2.1 license is
bundled with the app as `VLCKit-LICENSE.txt`.

Official release mapping:
https://github.com/videolan/vlckit/blob/master/Packaging/MobileVLCKit.json

Source and build instructions:
https://github.com/videolan/vlckit

Swift autolinking of MobileVLCKit is disabled for the app target so that its
manual linker entry follows the private FFmpeg archives. This prevents VLC's
exported FFmpeg symbols from being selected for the download remuxer.
