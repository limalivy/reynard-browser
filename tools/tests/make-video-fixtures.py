#!/usr/bin/env python3
"""Generate deterministic local media for the simulator component/UI tests."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1]).resolve()
root.mkdir(parents=True, exist_ok=True)


def ffmpeg(directory, *arguments):
    directory.mkdir(parents=True, exist_ok=True)
    subprocess.run(["ffmpeg", "-v", "error", "-y", *arguments], cwd=directory, check=True)


manifest = []
for duration in (9, 10, 11):
    path = root / f"video-{duration}s.mp4"
    ffmpeg(root, "-f", "lavfi", "-i", f"testsrc2=size=320x180:rate=30:duration={duration}",
           "-c:v", "libx264", "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(path))
    manifest.append({"file": path.name, "duration": duration,
                     "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
(root / "media-manifest.json").write_text(json.dumps(manifest, indent=2))
source = str(root / "video-11s.mp4")
hls = root / "hls"
for name, arguments in (
    ("ts", []), ("fmp4", ["-hls_segment_type", "fmp4"]),
    ("range", ["-hls_segment_type", "fmp4", "-hls_flags", "single_file"]),
):
    ffmpeg(hls / name, "-i", source, "-c:v", "libx264", "-g", "60", "-sc_threshold", "0",
           "-hls_time", "4", "-hls_list_size", "0", *arguments, "index.m3u8")
aes = hls / "aes"
aes.mkdir(parents=True, exist_ok=True)
(aes / "key.bin").write_bytes(bytes(range(16)))
(aes / "keyinfo").write_text(f"key.bin\n{aes / 'key.bin'}\n")
ffmpeg(aes, "-i", source, "-c:v", "libx264", "-g", "60", "-sc_threshold", "0",
       "-hls_time", "4", "-hls_list_size", "0", "-hls_key_info_file", "keyinfo", "index.m3u8")
ffmpeg(hls / "audio", "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000", "-t", "11",
       "-c:a", "aac", "-b:a", "96k", "-hls_time", "4", "-hls_list_size", "0",
       "-hls_segment_type", "fmp4", "index.m3u8")
(hls / "master.m3u8").write_text(
    '#EXTM3U\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="English",DEFAULT=YES,URI="audio/index.m3u8"\n'
    '#EXT-X-STREAM-INF:BANDWIDTH=1000,AUDIO="audio"\nts/index.m3u8\n'
    '#EXT-X-STREAM-INF:BANDWIDTH=2000,AUDIO="audio"\nfmp4/index.m3u8\n'
)
if not (root / "index.html").exists():
    (root / "index.html").write_text("<!doctype html><title>Not a video</title>")
print(root)
