# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 zahidzta

"""Verify and assemble architecture-specific macOS assets on a desktop draft."""

import argparse
import base64
import copy
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


REPOSITORY = "zahidzta/zownload_application"
WINDOWS_KEYS = {"windows-x86_64", "windows-x86_64-msi", "windows-x86_64-nsis"}
BASE_KEYS = WINDOWS_KEYS | {"linux-x86_64"}
MACOS_PACKAGES = {
    "darwin-aarch64": "aarch64",
    "darwin-x86_64": "x86_64",
}


def load(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def require(condition, message):
    if not condition:
        raise ValueError(message)


def asset_map(release):
    assets = release["assets"]
    names = {asset["name"]: asset for asset in assets}
    require(len(names) == len(assets), "duplicate draft asset name")
    return names


def asset_for_url(url, release):
    match = re.fullmatch(
        rf"https://api\.github\.com/repos/{REPOSITORY}/releases/assets/(\d+)", url
    )
    require(match is not None, f"unexpected updater URL: {url}")
    matches = [asset for asset in release["assets"] if str(asset["id"]) == match[1]]
    require(len(matches) == 1, f"updater asset ID is absent from draft: {match[1]}")
    return matches[0]["name"]


def base_asset_names(version):
    windows = {
        f"Zownload_{version}_x64-setup.exe",
        f"Zownload_{version}_x64-setup.exe.sig",
        f"Zownload_{version}_x64_en-US.msi",
        f"Zownload_{version}_x64_en-US.msi.sig",
    }
    linux = {
        f"Zownload_{version}_amd64.AppImage",
        f"Zownload_{version}_amd64.AppImage.sig",
        f"Zownload_{version}_amd64.deb",
        f"Zownload_{version}_amd64.deb.sig",
    }
    return windows | linux | {"latest.json"}


def macos_asset_names(version):
    names = set()
    for architecture in MACOS_PACKAGES.values():
        names.add(f"Zownload_{version}_{architecture}.dmg")
        archive = f"Zownload_{version}_{architecture}.app.tar.gz"
        names.update({archive, f"{archive}.sig"})
    return names


def check_release(release, version, macos=False, allow_partial_macos=False):
    require(release["draft"] is True, "release must remain a draft")
    require(release["tag_name"] == f"app-v{version}", "draft tag differs from app version")
    names = set(asset_map(release))
    base = base_asset_names(version)
    macos_names = macos_asset_names(version)
    if macos:
        require(names == base | macos_names, f"draft asset allowlist mismatch: {sorted(names)}")
    elif allow_partial_macos:
        require(base <= names <= base | macos_names,
                f"draft contains an unexpected asset: {sorted(names - (base | macos_names))}")
        added = names - base
        require(not added or added == macos_names,
                "draft contains an incomplete prior macOS asset set")
    else:
        require(names == base, f"draft asset allowlist mismatch: {sorted(names)}")


def signature_text(signature_dir, name):
    return (Path(signature_dir) / f"{name}.sig").read_text(encoding="utf-8").strip()


def check_base_metadata(latest, release, version, signature_dir):
    require(latest["version"] == version, "updater version differs from app version")
    platforms = latest["platforms"]
    require(set(platforms) in (BASE_KEYS, BASE_KEYS | set(MACOS_PACKAGES)),
            "baseline updater keys differ from the Windows/Linux release")
    names = asset_map(release)
    windows = {
        "windows-x86_64": f"Zownload_{version}_x64_en-US.msi",
        "windows-x86_64-msi": f"Zownload_{version}_x64_en-US.msi",
        "windows-x86_64-nsis": f"Zownload_{version}_x64-setup.exe",
    }
    for key, package in windows.items():
        entry = platforms[key]
        require(asset_for_url(entry["url"], release) == package,
                f"{key} targets the wrong Windows package")
        require(entry["signature"] == signature_text(signature_dir, package),
                f"{key} signature differs from the draft")

    appimage = f"Zownload_{version}_amd64.AppImage"
    linux_entry = platforms["linux-x86_64"]
    require(asset_for_url(linux_entry["url"], release) == appimage,
            "Linux updater does not target the existing AppImage")
    require(linux_entry["signature"] == signature_text(signature_dir, appimage),
            "Linux updater signature differs from the draft")
    require({f"{appimage}", f"{appimage}.sig"} <= set(names),
            "the existing Linux AppImage or signature is missing")
    deb_name = f"Zownload_{version}_amd64.deb"
    deb_url = names[deb_name].get("browser_download_url", "")
    prefix = f"https://github.com/{REPOSITORY}/releases/download/"
    require(deb_url.startswith(prefix), "existing Debian package has an unexpected download URL")
    deb_parts = deb_url[len(prefix):].split("/")
    require(len(deb_parts) == 2 and deb_parts[1] == deb_name and
            (deb_parts[0] == f"app-v{version}" or re.fullmatch(r"untagged-[0-9a-f]+", deb_parts[0])),
            "existing Debian package URL does not target the matching draft asset")
    if set(platforms) == BASE_KEYS | set(MACOS_PACKAGES):
        for key, architecture in MACOS_PACKAGES.items():
            package = f"Zownload_{version}_{architecture}.app.tar.gz"
            entry = platforms[key]
            require(asset_for_url(entry["url"], release) == package,
                    f"existing {key} entry targets the wrong updater archive")
            require({package, f"{package}.sig"} <= set(names),
                    f"existing {key} archive or signature is missing")
            require(entry["signature"] == signature_text(signature_dir, package),
                    f"existing {key} signature differs from the draft")


def macos_files(root, version, architecture=None):
    root = Path(root)
    require(root.is_dir(), "macOS staging directory is missing")
    expected = macos_asset_names(version)
    if architecture:
        require(architecture in MACOS_PACKAGES.values(),
                f"unknown macOS asset architecture: {architecture}")
        archive = f"Zownload_{version}_{architecture}.app.tar.gz"
        expected = {
            f"Zownload_{version}_{architecture}.dmg",
            archive,
            f"{archive}.sig",
        }
    actual = {path.name for path in root.iterdir() if path.is_file()}
    require(actual == expected, f"macOS package allowlist mismatch: {sorted(actual)}")
    require(not any(path.is_dir() for path in root.iterdir()),
            "macOS staging directory contains an unexpected directory")
    return {name: root / name for name in expected}


def verify_signatures(files, config, minisign):
    public_key = base64.b64decode(config["plugins"]["updater"]["pubkey"], validate=True)
    with tempfile.TemporaryDirectory(prefix="zownload-macos-signatures-") as directory:
        work = Path(directory)
        key = work / "updater.pub"
        key.write_bytes(public_key)
        for package_name in (name for name in files if name.endswith(".app.tar.gz")):
            signature_path = files[f"{package_name}.sig"]
            signature = work / f"{package_name}.minisig"
            signature.write_bytes(base64.b64decode(
                signature_path.read_text(encoding="utf-8").strip(), validate=True
            ))
            command = [minisign, "-V", "-p", str(key), "-m", str(files[package_name]),
                       "-x", str(signature)]
            result = subprocess.run(command, capture_output=True, text=True, check=False)
            require(result.returncode == 0,
                    f"{package_name} updater signature failed verification: {result.stderr[-500:]}")
            tampered = work / package_name
            shutil.copyfile(files[package_name], tampered)
            with tampered.open("ab") as output:
                output.write(b"\x00")
            result = subprocess.run(
                [minisign, "-V", "-p", str(key), "-m", str(tampered), "-x", str(signature)],
                capture_output=True, text=True, check=False,
            )
            require(result.returncode != 0,
                    f"{package_name} signature accepted a tampered package")


def check_uploaded_bytes(files, release):
    assets = asset_map(release)
    for name, path in files.items():
        asset = assets[name]
        require(asset["size"] == path.stat().st_size, f"uploaded {name} size differs")
        with path.open("rb") as source:
            digest = hashlib.file_digest(source, "sha256").hexdigest()
        require(asset["digest"] == f"sha256:{digest}",
                f"uploaded {name} SHA-256 differs from the draft")


def check_final_metadata(release, baseline, final, version, signatures, bundle_root):
    check_release(release, version, macos=True)
    check_base_metadata(baseline, release, version, signatures)
    require(final["version"] == version, "combined updater version differs from the app")
    require(set(final["platforms"]) == BASE_KEYS | set(MACOS_PACKAGES),
            "combined metadata has unexpected updater targets")
    require({key: value for key, value in final.items() if key != "platforms"} ==
            {key: value for key, value in baseline.items() if key != "platforms"},
            "combined metadata changed existing top-level fields")
    baseline_platforms = {key: baseline["platforms"][key] for key in BASE_KEYS}
    require({key: final["platforms"][key] for key in BASE_KEYS} == baseline_platforms,
            "combined metadata changed Windows/Linux updater entries")

    assets = asset_map(release)
    for key, architecture in MACOS_PACKAGES.items():
        package = f"Zownload_{version}_{architecture}.app.tar.gz"
        entry = final["platforms"][key]
        require(asset_for_url(entry["url"], release) == package,
                f"{key} targets the wrong updater archive")
        require(entry["signature"] == signature_text(bundle_root, package),
                f"{key} signature differs from its updater archive")
        require(f"{package}.sig" in assets, f"{key} signature asset is missing")


def assemble_metadata(release, baseline, files, version, signatures, output):
    check_release(release, version, macos=True)
    check_base_metadata(baseline, release, version, signatures)
    check_uploaded_bytes(files, release)
    combined = copy.deepcopy(baseline)
    assets = asset_map(release)
    for key, architecture in MACOS_PACKAGES.items():
        package = f"Zownload_{version}_{architecture}.app.tar.gz"
        combined["platforms"][key] = {
            "signature": files[f"{package}.sig"].read_text(encoding="utf-8").strip(),
            "url": f"https://api.github.com/repos/{REPOSITORY}/releases/assets/{assets[package]['id']}",
        }
    Path(output).write_text(json.dumps(combined, indent=2) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("stage", choices=["preflight", "signed", "assemble", "verify", "metadata"])
    parser.add_argument("--config", required=True)
    parser.add_argument("--release")
    parser.add_argument("--latest")
    parser.add_argument("--signatures")
    parser.add_argument("--bundle-root")
    parser.add_argument("--output")
    parser.add_argument("--version")
    parser.add_argument("--architecture", choices=sorted(set(MACOS_PACKAGES.values())))
    parser.add_argument("--minisign", default="minisign")
    arguments = parser.parse_args()
    config = load(arguments.config)
    version = arguments.version or config["version"]

    if arguments.stage == "signed":
        files = macos_files(arguments.bundle_root, version, arguments.architecture)
        verify_signatures(files, config, arguments.minisign)
        print("Signed macOS package allowlist and updater tamper rejection passed.")
        return

    require(arguments.release and arguments.latest and arguments.signatures,
            "release, latest, and signature paths are required")
    release = load(arguments.release)
    baseline = load(arguments.latest)
    if arguments.stage == "preflight":
        check_release(release, version, allow_partial_macos=True)
    else:
        check_release(release, version, macos=True)
    check_base_metadata(baseline, release, version, arguments.signatures)
    if arguments.stage == "preflight":
        print("Owner-created unpublished draft and Windows/Linux metadata verified.")
        return

    require(arguments.bundle_root, "macOS staging directory is required")
    files = macos_files(arguments.bundle_root, version)
    verify_signatures(files, config, arguments.minisign)
    check_uploaded_bytes(files, release)
    if arguments.stage == "assemble":
        require(arguments.output, "combined metadata output path is required")
        assemble_metadata(release, baseline, files, version, arguments.signatures,
                          arguments.output)
        print("Windows/Linux metadata preserved; both macOS updater entries assembled.")
        return
    if arguments.stage == "verify":
        require(arguments.output, "combined metadata path is required")
        check_final_metadata(release, baseline, load(arguments.output), version,
                             arguments.signatures, arguments.bundle_root)
        print("Draft asset allowlist, Windows/Linux preservation, signatures, and macOS updater targets passed.")
        return
    require(arguments.output, "downloaded latest.json path is required")
    check_final_metadata(release, baseline, load(arguments.output), version,
                         arguments.signatures, arguments.bundle_root)
    print("Uploaded latest.json preserves existing platform entries and maps both macOS architectures.")


if __name__ == "__main__":
    main()
