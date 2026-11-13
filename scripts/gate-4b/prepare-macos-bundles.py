# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 zahidzta

"""Validate and stage one architecture's Tauri macOS release bundles."""

import argparse
import hashlib
from pathlib import Path
import shutil
import subprocess
import sys


ARCHITECTURES = {
    "x86_64": ("x86_64", "x86_64", "x64", "10.15"),
    "arm64": ("arm64", "aarch64", "aarch64", "11.0"),
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def output(command):
    result = subprocess.run(command, capture_output=True, text=True, check=False)
    require(result.returncode == 0, f"command failed: {' '.join(command)}: {result.stderr[-500:]}")
    return result.stdout.strip()


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def names_in(directory):
    return {path.name for path in directory.iterdir()}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--bundle-root", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--architecture", choices=ARCHITECTURES, required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--unsigned", action="store_true")
    arguments = parser.parse_args()

    (architecture, asset_architecture, dmg_architecture,
     minimum_system_version) = ARCHITECTURES[arguments.architecture]
    bundle_root = Path(arguments.bundle_root)
    dmg_root = bundle_root / "dmg"
    macos_root = bundle_root / "macos"
    share_root = bundle_root / "share"
    bundle_entries = list(bundle_root.iterdir())
    observed_entries = sorted(
        f"{path.name}{'/' if path.is_dir() else ''}" for path in bundle_entries
    )
    require({path.name for path in bundle_entries} == {"dmg", "macos", "share"} and
            all(path.is_dir() for path in bundle_entries),
            f"Tauri created an unexpected bundle format: {observed_entries}")
    create_dmg_root = share_root / "create-dmg"
    support_root = create_dmg_root / "support"
    support_files = {"template.applescript", "eula-resources-template.xml"}
    require(
        names_in(share_root) == {"create-dmg"} and
        create_dmg_root.is_dir() and
        names_in(create_dmg_root) == {"support"} and
        support_root.is_dir() and
        names_in(support_root) == support_files and
        all(path.is_file() for path in support_root.iterdir()),
        "Tauri created unexpected DMG support files")
    dmg_entries = list(dmg_root.iterdir())
    expected_dmg = f"Zownload_{arguments.version}_{dmg_architecture}.dmg"
    expected_dmg_files = {expected_dmg, "bundle_dmg.sh", "icon.icns"}
    require(
        {path.name for path in dmg_entries} == expected_dmg_files and
        all(path.is_file() for path in dmg_entries),
        f"Tauri created unexpected DMG output files: "
        f"{sorted(path.name for path in dmg_entries)}")

    app = macos_root / "Zownload.app"
    archive = macos_root / "Zownload.app.tar.gz"
    signature = macos_root / "Zownload.app.tar.gz.sig"
    expected_macos_files = {app.name} if arguments.unsigned else {
        app.name, archive.name, signature.name
    }
    require({path.name for path in macos_root.iterdir()} == expected_macos_files,
            "Tauri created unexpected macOS updater bundle files")
    require(app.is_dir(), "Tauri macOS app bundle is missing")
    if not arguments.unsigned:
        require(archive.is_file() and signature.is_file(),
                "Tauri macOS updater archive or signature is missing")

    info = app / "Contents" / "Info.plist"
    require(info.is_file(), "Tauri app Info.plist is missing")
    executable_name = output([
        "/usr/libexec/PlistBuddy", "-c", "Print :CFBundleExecutable", str(info)
    ])
    executable = app / "Contents" / "MacOS" / executable_name
    require(executable.is_file(), "Tauri app executable is missing")
    archs = set(output(["lipo", "-archs", str(executable)]).split())
    require(archs == {architecture}, f"app binary architectures differ: {sorted(archs)}")
    minimum = output(["/usr/libexec/PlistBuddy", "-c", "Print :LSMinimumSystemVersion", str(info)])
    require(minimum == minimum_system_version,
            f"app minimum macOS version is {minimum}, expected {minimum_system_version}")
    app_version = output(["/usr/libexec/PlistBuddy", "-c", "Print :CFBundleShortVersionString", str(info)])
    require(app_version == arguments.version,
            f"app bundle version is {app_version}, expected {arguments.version}")

    destination = Path(arguments.output)
    destination.mkdir(parents=True, exist_ok=True)
    require(not any(destination.iterdir()), "staging directory must be empty")
    dmg = dmg_root / expected_dmg
    names = {dmg: f"Zownload_{arguments.version}_{asset_architecture}.dmg"}
    if not arguments.unsigned:
        names[archive] = f"Zownload_{arguments.version}_{asset_architecture}.app.tar.gz"
        names[signature] = f"Zownload_{arguments.version}_{asset_architecture}.app.tar.gz.sig"
    for source, name in names.items():
        target = destination / name
        shutil.copy2(source, target)
        print(f"{target.name} SHA-256 {sha256(target)}")
    print(f"Architecture {architecture}; minimum macOS {minimum_system_version}; version {arguments.version}.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError) as error:
        print(f"macOS bundle validation failed: {error}", file=sys.stderr)
        raise SystemExit(1)
