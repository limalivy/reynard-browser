#!/usr/bin/env python3
"""Link the real remux bridge with Gecko using each app configuration's order."""
import json
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[2]
sdk, gecko = sys.argv[1:]
assert sdk in ("iphoneos", "iphonesimulator")
target = "arm64-apple-ios13.0" + ("-simulator" if sdk == "iphonesimulator" else "")
sysroot = subprocess.check_output(["xcrun", "--sdk", sdk, "--show-sdk-path"], text=True).strip()
project = json.loads(subprocess.check_output([
    "plutil", "-convert", "json", "-o", "-", str(root / "browser/Reynard.xcodeproj/project.pbxproj")
]))["objects"]
app = next(obj for obj in project.values() if obj.get("isa") == "PBXNativeTarget" and obj.get("name") == "Reynard")
configs = project[app["buildConfigurationList"]]["buildConfigurations"]
media_flags = {"-lmozavcodec", "-lmozavutil", "-Wl,-hidden-lavformat", "-Wl,-hidden-lavcodec", "-Wl,-hidden-lavutil"}
for key in configs:
    config = project[key]
    all_flags = config["buildSettings"]["OTHER_LDFLAGS"]
    flags = []
    for index, flag in enumerate(all_flags):
        if flag in media_flags:
            flags.append(flag)
        elif flag == "-framework" and all_flags[index + 1] == "MobileVLCKit":
            flags.extend([flag, "MobileVLCKit"])
    assert len(flags) == len(media_flags) + 2
    swift_flags = config["buildSettings"]["OTHER_SWIFT_FLAGS"]
    assert "-disable-autolink-framework -Xfrontend MobileVLCKit" in swift_flags
    with tempfile.TemporaryDirectory() as directory:
        swift_source = Path(directory) / "PlayerImport.swift"
        swift_source.write_text("import MobileVLCKit\nfunc makePlayer() -> VLCMediaPlayer { VLCMediaPlayer() }\n")
        swift_object = Path(directory) / "PlayerImport.o"
        subprocess.run([
            "xcrun", "--sdk", sdk, "swiftc", "-target", target, "-sdk", sysroot,
            "-module-cache-path", str(Path(directory) / "ModuleCache"),
            "-F", str(root / f"support/vlckit/build/{sdk}"),
            *[flag for flag in shlex.split(swift_flags) if flag != "$(inherited)"],
            "-c", str(swift_source), "-o", str(swift_object),
        ], check=True)
        options = subprocess.check_output(["otool", "-l", str(swift_object)], text=True)
        assert "MobileVLCKit" not in options, "Swift autolink bypassed the explicit framework order"
        executable = str(Path(directory) / "media-link-test")
        subprocess.run([
            "xcrun", "--sdk", sdk, "clang", "-target", target, "-isysroot", sysroot,
            "-I" + str(root / "browser/Reynard/Bridging"),
            "-I" + str(root / f"support/media/build/{sdk}/include"),
            str(root / "browser/Reynard/Client/Stores/VideoRemux.c"),
            str(root / "tools/tests/VideoRemuxTests.c"),
            "-L" + str(Path(gecko).resolve()), "-L" + str(root / f"support/media/build/{sdk}/lib"),
            "-F" + str(root / f"support/vlckit/build/{sdk}"),
            "-Wl,-dead_strip", *flags, "-o", executable,
        ], check=True)
        imports = subprocess.check_output(["xcrun", "nm", "-u", executable], text=True)
        assert not re.search(r"\b_(?:av[a-z]*|ff)_\w+", imports), "Remuxer resolved a media symbol from Gecko's dylibs"
        print(f"PASS {config['name']}: remux bridge uses its private FFmpeg with Gecko and VLC present")
