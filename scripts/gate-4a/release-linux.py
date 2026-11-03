# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 zahidzta

"""Check and assemble the owner-created Windows/Linux draft release."""

import argparse
import base64
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


REPOSITORY = "zahidzta/zownload_application"
WINDOWS_KEYS = {"windows-x86_64", "windows-x86_64-msi", "windows-x86_64-nsis"}


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


def check_release(release, version, linux_names=()):
    require(release["draft"] is True, "release must remain a draft")
    require(release["tag_name"] == f"app-v{version}", "draft tag differs from app version")
    names = set(asset_map(release))
    windows = {
        f"Zownload_{version}_x64-setup.exe",
        f"Zownload_{version}_x64-setup.exe.sig",
        f"Zownload_{version}_x64_en-US.msi",
        f"Zownload_{version}_x64_en-US.msi.sig",
        "latest.json",
    }
    require(names == windows | set(linux_names), f"draft asset allowlist mismatch: {sorted(names)}")


def check_windows(latest, release, version, signature_dir):
    require(latest["version"] == version, "updater version differs from app version")
    require(set(latest["platforms"]) == WINDOWS_KEYS, "Windows updater keys differ from baseline")
    packages = {
        "windows-x86_64": f"Zownload_{version}_x64_en-US.msi",
        "windows-x86_64-msi": f"Zownload_{version}_x64_en-US.msi",
        "windows-x86_64-nsis": f"Zownload_{version}_x64-setup.exe",
    }
    for key, package in packages.items():
        entry = latest["platforms"][key]
        require(asset_for_url(entry["url"], release) == package, f"{key} targets wrong package")
        signature = (Path(signature_dir) / f"{package}.sig").read_text(encoding="utf-8").strip()
        require(entry["signature"] == signature, f"{key} signature differs from draft")


def linux_packages(root, version, signed=True):
    root = Path(root)
    require({p.name for p in root.iterdir() if p.is_dir()} == {"appimage", "deb"},
            "Linux build has unexpected bundle directories")
    package_names = {
        "appimage": f"Zownload_{version}_amd64.AppImage",
        "deb": f"Zownload_{version}_amd64.deb",
    }
    packages = {}
    for directory, name in package_names.items():
        files = {p.name for p in (root / directory).iterdir() if p.is_file()}
        expected = {name, f"{name}.sig"} if signed else {name}
        require(files == expected, f"unexpected {directory} bundle files: {sorted(files)}")
        packages[directory] = root / directory / name
    return packages


def verify_signatures(packages, config, minisign):
    public_key = base64.b64decode(config["plugins"]["updater"]["pubkey"], validate=True)
    with tempfile.TemporaryDirectory(prefix="zownload-linux-signatures-") as directory:
        work = Path(directory)
        key = work / "updater.pub"
        key.write_bytes(public_key)
        for name, package in packages.items():
            signature = (work / f"{name}.minisig")
            signature.write_bytes(base64.b64decode(
                Path(f"{package}.sig").read_text(encoding="utf-8").strip(), validate=True
            ))
            command = [minisign, "-V", "-p", str(key), "-m", str(package), "-x", str(signature)]
            good = subprocess.run(command, capture_output=True, text=True, check=False)
            require(good.returncode == 0, f"{name} updater signature failed verification: {good.stderr[-500:]}")
            tampered = work / package.name
            shutil.copyfile(package, tampered)
            with tampered.open("ab") as output:
                output.write(b"\x00")
            bad = subprocess.run(
                [minisign, "-V", "-p", str(key), "-m", str(tampered), "-x", str(signature)],
                capture_output=True, text=True, check=False,
            )
            require(bad.returncode != 0, f"{name} signature accepted a tampered package")
            tampered.unlink()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("stage", choices=["preflight", "unsigned", "signed", "assemble", "verify"])
    parser.add_argument("--config", required=True)
    parser.add_argument("--release")
    parser.add_argument("--latest")
    parser.add_argument("--windows-signatures")
    parser.add_argument("--bundle-root")
    parser.add_argument("--output")
    parser.add_argument("--minisign", default="minisign")
    arguments = parser.parse_args()
    config = load(arguments.config)
    version = config["version"]
    if arguments.stage == "unsigned":
        require(arguments.bundle_root, "Linux bundle root is required")
        packages = linux_packages(arguments.bundle_root, version, signed=False)
        print(f"Unsigned Linux package allowlist passed: {', '.join(p.name for p in packages.values())}.")
        return
    if arguments.stage == "signed":
        require(arguments.bundle_root, "Linux bundle root is required")
        packages = linux_packages(arguments.bundle_root, version)
        verify_signatures(packages, config, arguments.minisign)
        print("Signed Linux package allowlist and tamper rejection passed.")
        return
    require(arguments.release and arguments.latest and arguments.windows_signatures,
            "release, latest, and Windows signature paths are required")
    release = load(arguments.release)
    baseline = load(arguments.latest)
    if arguments.stage == "preflight":
        check_release(release, version)
        check_windows(baseline, release, version, arguments.windows_signatures)
        print("Owner-created Windows draft and updater metadata verified.")
        return

    require(arguments.bundle_root, "Linux bundle root is required")
    packages = linux_packages(arguments.bundle_root, version)
    verify_signatures(packages, config, arguments.minisign)
    linux_names = {path.name for path in packages.values()} | {
        f"{path.name}.sig" for path in packages.values()
    }
    check_release(release, version, linux_names)
    check_windows(baseline, release, version, arguments.windows_signatures)
    appimage = packages["appimage"]
    appimage_asset = asset_map(release)[appimage.name]
    entry = {
        "signature": Path(f"{appimage}.sig").read_text(encoding="utf-8").strip(),
        "url": f"https://api.github.com/repos/{REPOSITORY}/releases/assets/{appimage_asset['id']}",
    }
    if arguments.stage == "assemble":
        require(arguments.output, "output path is required")
        baseline["platforms"]["linux-x86_64"] = entry
        Path(arguments.output).write_text(json.dumps(baseline, indent=2) + "\n", encoding="utf-8")
        print("Combined Windows and AppImage updater metadata assembled.")
        return

    final = load(arguments.output)
    require(set(final["platforms"]) == WINDOWS_KEYS | {"linux-x86_64"},
            "combined metadata has unexpected updater targets")
    require({key: value for key, value in final.items() if key != "platforms"} ==
            {key: value for key, value in baseline.items() if key != "platforms"},
            "combined metadata changed baseline fields")
    require({key: final["platforms"][key] for key in WINDOWS_KEYS} == baseline["platforms"],
            "Windows updater entries changed")
    require(final["platforms"]["linux-x86_64"] == entry, "AppImage updater entry is wrong")
    require(asset_for_url(entry["url"], release) == appimage.name, "AppImage URL targets wrong package")
    deb = packages["deb"]
    deb_url = asset_map(release)[deb.name]["browser_download_url"]
    require(deb_url == f"https://github.com/{REPOSITORY}/releases/download/app-v{version}/{deb.name}",
            "direct .deb link does not target the matching package")
    print("Combined draft allowlist, updater signatures, tamper rejection, and .deb link verified.")


if __name__ == "__main__":
    main()
