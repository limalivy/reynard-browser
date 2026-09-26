# Video remux library

Reynard builds FFmpeg 8.1.3 from the official release source using
`tools/development/build-media.sh` (device) or `--simulator` (arm64 Simulator).
The archive URL and SHA-256 are pinned in that script. Build products and source
archives are ignored by Git. A matching Xcode SDK is required for each target.

Only container demuxers, parsers, built-in AAC/H264/HEVC decoders for stream
inspection, MP4 muxing and local file/crypto protocols are enabled. Downloads use
Gecko with the originating document's principal, cookie
jar, referrer policy and User-Agent. FFmpeg receives generated local playlists;
it has no network protocols. No GPL or nonfree options or external codecs are
enabled. The library is LGPL 2.1 or later; its license is bundled in the app.

Sources: https://ffmpeg.org/releases/ffmpeg-8.1.3.tar.xz

The bridge source is `browser/Reynard/Client/Stores/VideoRemux.c`. To rebuild or
relink, build the libraries with the script, then build the Reynard Xcode target.
The complete application source, bridge, build flags and linking configuration
are in this repository. `support/media/build/<SDK>/lib` contains the static
libraries and `objects` contains their intermediate build objects.

The private FFmpeg archives must precede XUL and Gecko's mozav libraries in the
app's linker flags. Gecko exports some of the same FFmpeg symbols; resolving an
internal static reference against its dylibs can cause ARM64 relocation errors
or mix incompatible library versions. `tools/tests/test-media-link.py` tests the
actual Debug and Release flag order against Gecko and rejects imported media
symbols in the remux bridge.

Current scope: finite HLS, highest bandwidth variant, default external audio,
MPEG-TS/fMP4, byte ranges and ordinary AES-128 identity keys. Live playlists,
SAMPLE-AES/DRM and DASH reconstruction are rejected. Resource discovery does not
disable MSE or modify page playback APIs. YouTube support is not claimed.
