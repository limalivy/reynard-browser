#!/bin/sh
set -eu
FIXTURES="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/fixtures"
mkdir -p "$FIXTURES"
ffmpeg -hide_banner -loglevel error -y -f lavfi -i 'testsrc2=size=320x180:rate=30:duration=30' \
    -f lavfi -i 'sine=frequency=440:sample_rate=48000:duration=30' \
    -c:v libx264 -preset veryfast -pix_fmt yuv420p -c:a aac -movflags +faststart "$FIXTURES/player-mp4.mp4"
ffmpeg -hide_banner -loglevel error -y -i "$FIXTURES/player-mp4.mp4" -c copy "$FIXTURES/player-mkv.mkv"
ffmpeg -hide_banner -loglevel error -y -i "$FIXTURES/player-mp4.mp4" \
    -c:v libvpx-vp9 -deadline realtime -cpu-used 8 -c:a libopus "$FIXTURES/player-webm.webm"
if [ -n "${1:-}" ]; then
    cp "$1" "$FIXTURES/player-hls.mp4"
else
    ffmpeg -hide_banner -loglevel error -y -i "$FIXTURES/player-mp4.mp4" -t 11 -c copy \
        -hls_time 3 -hls_playlist_type vod "$FIXTURES/sample.m3u8"
    ffmpeg -hide_banner -loglevel error -y -i "$FIXTURES/sample.m3u8" -c copy "$FIXTURES/player-hls.mp4"
fi
printf 'Invalid video fixture\n' > "$FIXTURES/player-invalid.mp4"

ffmpeg -hide_banner -loglevel error -y -f lavfi -i "testsrc2=size=180x320:rate=30:duration=30" \
    -c:v libx264 -preset veryfast -pix_fmt yuv420p -movflags +faststart "$FIXTURES/player-portrait.mp4"
