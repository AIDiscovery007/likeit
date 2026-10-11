#!/usr/bin/env python3
"""Build only the bundled desktop; never launches it or requests permissions."""
from pathlib import Path
import hashlib
import json
import plistlib
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
DESTINATION = ROOT / "assets/native/Likeit Desktop.app"
adapter = json.loads((ROOT / "assets/native/BUILD.json").read_text())
for name, expected in adapter["sha256"].items():
    if name.startswith("MediaRemoteAdapter.framework/") or name in ["mediaremote-adapter.pl", "LICENSE-mediaremote-adapter"]:
        if hashlib.sha256((ROOT / "assets/native" / name).read_bytes()).hexdigest() != expected:
            raise SystemExit(f"Bundled adapter checksum mismatch: {name}")
sdk = subprocess.check_output(["xcrun", "--show-sdk-path"], text=True).strip()
sources = sorted((ROOT / "native").glob("Desktop*.swift")) + [ROOT / "native/ImmersiveCore.swift"]
with tempfile.TemporaryDirectory(prefix="likeit-desktop-build-") as directory:
    stage = Path(directory)
    app = stage / "Likeit Desktop.app"
    contents = app / "Contents"
    (contents / "MacOS").mkdir(parents=True)
    resources = contents / "Resources"
    resources.mkdir()
    # The app owns its read-only adapter and resolves it from Bundle.main.
    for name in ["MediaRemoteAdapter.framework", "mediaremote-adapter.pl", "LICENSE-mediaremote-adapter"]:
        source = ROOT / "assets/native" / name
        if source.is_dir():
            # Raycast resolves symlinks while copying assets. Ship a flat framework
            # so the signed bundle contains only regular files and directories.
            framework = resources / name
            framework.mkdir()
            version = source / "Versions/A"
            for entry in ["MediaRemoteAdapter", "Headers", "Resources"]:
                origin = version / entry
                if origin.is_dir():
                    shutil.copytree(origin, framework / entry)
                else:
                    shutil.copy2(origin, framework / entry)
            subprocess.run(["xcrun", "install_name_tool", "-id",
                            "@rpath/MediaRemoteAdapter.framework/MediaRemoteAdapter",
                            str(framework / "MediaRemoteAdapter")], check=True)
            subprocess.run(["codesign", "--force", "--sign", "-", str(framework)], check=True)
            subprocess.run(["codesign", "--verify", "--strict", str(framework)], check=True)
        else:
            shutil.copy2(source, resources / name)
    with (contents / "Info.plist").open("wb") as output:
        plistlib.dump({
            "CFBundleExecutable": "Likeit Desktop", "CFBundleIdentifier": "com.likeit.desktop",
            "CFBundleName": "Likeit Desktop", "CFBundleDisplayName": "Likeit Desktop",
            "CFBundlePackageType": "APPL", "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0",
            "LSMinimumSystemVersion": "14.2", "NSHighResolutionCapable": True,
            "NSAudioCaptureUsageDescription": "Likeit 仅分析网易云音乐的实时音频，让桌面音响随音乐律动。音频不录制、不保存、不上传。",
            "CFBundleURLTypes": [{"CFBundleURLName": "com.likeit.desktop.open", "CFBundleURLSchemes": ["likeit-desktop"]}],
        }, output)
    for arch in ["arm64", "x86_64"]:
        subprocess.run(["xcrun", "swiftc", "-O", "-parse-as-library", "-target", arch + "-apple-macosx14.2", "-sdk", sdk, *map(str, sources), "-framework", "AppKit", "-framework", "SwiftUI", "-framework", "CoreAudio", "-framework", "Accelerate", "-o", str(stage / arch)], check=True)
    binary = contents / "MacOS/Likeit Desktop"
    subprocess.run(["xcrun", "lipo", "-create", str(stage / "arm64"), str(stage / "x86_64"), "-output", str(binary)], check=True)
    entitlements = stage / "desktop.entitlements"
    entitlements.write_bytes(plistlib.dumps({"com.apple.security.device.audio-input": True}))
    subprocess.run(["codesign", "--force", "--deep", "--options", "runtime", "--entitlements", str(entitlements), "--sign", "-", str(app)], check=True)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    subprocess.run(["xcrun", "lipo", str(binary), "-verify_arch", "arm64", "x86_64"], check=True)
    if any(path.is_symlink() for path in app.rglob("*")):
        raise SystemExit("Desktop bundle must not contain symlinks")
    if DESTINATION.exists():
        shutil.rmtree(DESTINATION)
    shutil.copytree(app, DESTINATION, symlinks=True)
(ROOT / "assets/native/DESKTOP-BUILD.json").write_text(json.dumps({
    "adapterCommit": adapter["sourceCommit"],
    "compiler": subprocess.check_output(["xcrun", "swiftc", "--version"], text=True).strip(),
    "sdkVersion": subprocess.check_output(["xcrun", "--show-sdk-version"], text=True).strip(),
    "buildCommand": "python3 scripts/build-desktop.py",
    "adapterLayout": "flat framework, no symlinks; install name adjusted before signing",
    "architectures": ["arm64", "x86_64"], "minimumMacOS": "14.2", "signing": "ad-hoc, hardened runtime",
    "sources": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources + [Path(__file__)]},
    "files": {str(p.relative_to(DESTINATION)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(DESTINATION.rglob("*")) if p.is_file() and not p.is_symlink()},
}, indent=2) + "\n")
