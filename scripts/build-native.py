#!/usr/bin/env python3
"""Developer-only build; no downloads, installs, or media commands."""
from pathlib import Path
import hashlib
import json
import plistlib
import shlex
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "vendor/mediaremote-adapter"
ASSETS = ROOT / "assets/native"
manifest = json.loads((SOURCE / "SOURCE.json").read_text())
for name, expected in manifest["files"].items():
    if hashlib.sha256((SOURCE / name).read_bytes()).hexdigest() != expected:
        raise SystemExit(f"Upstream source checksum mismatch: {name}")

sdk = subprocess.check_output(["xcrun", "--show-sdk-path"], text=True).strip()
commands = []


def run(command):
    commands.append(shlex.join(command))
    subprocess.run(command, check=True)


sources = [
    "src/adapter/" + name + ".m"
    for name in ["env", "get", "globals", "keys", "now_playing", "repeat", "seek",
                 "send", "shuffle", "speed", "stream", "test"]
] + ["src/private/MediaRemote.m", "src/utility/Debounce.m", "src/utility/helpers.m"]

with tempfile.TemporaryDirectory(prefix="likeit-native-build-") as directory:
    stage = Path(directory)
    framework = stage / "MediaRemoteAdapter.framework"
    version = framework / "Versions/A"
    (version / "Resources").mkdir(parents=True)
    (version / "Headers").mkdir()
    (framework / "Versions/Current").symlink_to("A")
    for name in ["MediaRemoteAdapter", "Resources", "Headers"]:
        (framework / name).symlink_to("Versions/Current/" + name)
    shutil.copy2(SOURCE / "LICENSE", version / "Resources/LICENSE")
    shutil.copy2(SOURCE / "include/MediaRemoteAdapter.h", version / "Headers/MediaRemoteAdapter.h")
    with (version / "Resources/Info.plist").open("wb") as output:
        plistlib.dump({
            "CFBundleExecutable": "MediaRemoteAdapter",
            "CFBundleIdentifier": "com.vandenbe.MediaRemoteAdapter",
            "CFBundleName": "MediaRemoteAdapter", "CFBundlePackageType": "FMWK",
            "CFBundleShortVersionString": "0.1", "CFBundleVersion": "0.1.0",
        }, output)
    for arch in ["arm64", "x86_64"]:
        run(["xcrun", "clang", "-dynamiclib", "-arch", arch, "-isysroot", sdk,
             "-mmacosx-version-min=13.0", "-fobjc-arc", "-fvisibility=default",
             "-I" + str(SOURCE / "include"), "-I" + str(SOURCE / "src"),
             *[str(SOURCE / name) for name in sources],
             "-framework", "Foundation", "-framework", "AppKit",
             "-framework", "UniformTypeIdentifiers", "-install_name",
             "@rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter",
             "-o", str(stage / arch)])
    run(["xcrun", "lipo", "-create", str(stage / "arm64"), str(stage / "x86_64"),
         "-output", str(version / "MediaRemoteAdapter")])
    run(["/usr/bin/codesign", "--force", "--deep", "--sign", "-", str(framework)])
    run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(framework)])
    run(["xcrun", "lipo", str(version / "MediaRemoteAdapter"), "-verify_arch", "arm64", "x86_64"])
    for arch in ["arm64", "x86_64"]:
        run(["xcrun", "swiftc", "-O", "-target", arch + "-apple-macosx13.0", "-sdk", sdk,
             str(ROOT / "native/LikeitController.swift"), "-framework", "AppKit",
             "-framework", "ApplicationServices", "-o", str(stage / ("controller-" + arch))])
    controller = stage / "likeit-controller"
    run(["xcrun", "lipo", "-create", str(stage / "controller-arm64"), str(stage / "controller-x86_64"),
         "-output", str(controller)])
    run(["/usr/bin/codesign", "--force", "--sign", "-", str(controller)])
    run(["/usr/bin/codesign", "--verify", "--strict", str(controller)])
    run(["xcrun", "lipo", str(controller), "-verify_arch", "arm64", "x86_64"])
    ASSETS.mkdir(parents=True, exist_ok=True)
    destination = ASSETS / framework.name
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(framework, destination, symlinks=True)
    shutil.copy2(SOURCE / "bin/mediaremote-adapter.pl", ASSETS / "mediaremote-adapter.pl")
    shutil.copy2(SOURCE / "LICENSE", ASSETS / "LICENSE-mediaremote-adapter")
    shutil.copy2(controller, ASSETS / "likeit-controller")

(ASSETS / "BUILD.json").write_text(json.dumps({
    "sourceCommit": manifest["commit"],
    "architectures": ["arm64", "x86_64"],
    "controllerSourceSHA256": hashlib.sha256((ROOT / "native/LikeitController.swift").read_bytes()).hexdigest(),
    "buildScriptSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    "compiler": subprocess.check_output(["xcrun", "clang", "--version"], text=True).strip(),
    "commands": [command.replace(str(ROOT), "<PROJECT>").replace(str(stage), "<BUILD>") for command in commands],
    "sha256": {str(path.relative_to(ASSETS)): hashlib.sha256(path.read_bytes()).hexdigest()
               for path in sorted(ASSETS.rglob("*")) if path.is_file() and not path.is_symlink()
               and path.name != "BUILD.json"},
}, indent=2) + "\n")
