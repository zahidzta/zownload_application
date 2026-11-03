# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 zahidzta

"""Offline regression for Linux draft assembly and signature rejection."""

import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[2]
VERIFIER = ROOT / "scripts/gate-4a/release-linux.py"
FIXTURES = ROOT / "tests/fixtures/app-updates"
VERSION = "0.0.1"
REPOSITORY = "zahidzta/zownload_application"


def run(stage, root, minisign, expected=0, **paths):
    command = [sys.executable, str(VERIFIER), stage, "--config", str(root / "config.json")]
    for key, value in paths.items():
        command += ["--" + key.replace("_", "-"), str(value)]
    command += ["--minisign", minisign]
    result = subprocess.run(command, capture_output=True, text=True, check=False)
    if (result.returncode == 0) != (expected == 0):
        raise AssertionError(f"{stage} returned {result.returncode}: {result.stdout}{result.stderr[-1000:]}")


def main(minisign):
    with tempfile.TemporaryDirectory(prefix="zownload-4a-test-") as temporary:
        root = Path(temporary)
        bundle = root / "bundle"
        appimage = bundle / "appimage" / f"Zownload_{VERSION}_amd64.AppImage"
        deb = bundle / "deb" / f"Zownload_{VERSION}_amd64.deb"
        windows = root / "windows"
        windows.mkdir()
        signature = (FIXTURES / "update-fixture.bin.sig").read_text(encoding="utf-8").strip()
        config = {
            "version": VERSION,
            "plugins": {"updater": {"pubkey": (FIXTURES / "test-key.pub").read_text().strip()}},
        }
        (root / "config.json").write_text(json.dumps(config), encoding="utf-8")
        for package in (appimage, deb):
            package.parent.mkdir(parents=True)
            shutil.copyfile(FIXTURES / "update-fixture.bin", package)
            Path(f"{package}.sig").write_text(signature, encoding="utf-8")

        windows_names = [f"Zownload_{VERSION}_x64-setup.exe", f"Zownload_{VERSION}_x64_en-US.msi"]
        assets = []
        platforms = {}
        for index, name in enumerate(windows_names, 101):
            (windows / f"{name}.sig").write_text(signature, encoding="utf-8")
            assets += [{"id": index, "name": name}, {"id": index + 100, "name": f"{name}.sig"}]
        assets.append({"id": 999, "name": "latest.json"})
        for key, asset_id in (("windows-x86_64", 102), ("windows-x86_64-msi", 102),
                              ("windows-x86_64-nsis", 101)):
            platforms[key] = {
                "signature": signature,
                "url": f"https://api.github.com/repos/{REPOSITORY}/releases/assets/{asset_id}",
            }
        baseline = {"version": VERSION, "notes": "keep", "platforms": platforms}
        baseline_path = root / "baseline.json"
        baseline_path.write_text(json.dumps(baseline), encoding="utf-8")
        release = {"draft": True, "tag_name": f"app-v{VERSION}", "assets": assets}
        release_path = root / "release.json"
        release_path.write_text(json.dumps(release), encoding="utf-8")
        common = {"release": release_path, "latest": baseline_path, "windows_signatures": windows}
        run("preflight", root, minisign, **common)
        run("signed", root, minisign, bundle_root=bundle)

        for index, package in enumerate((appimage, deb), 301):
            release["assets"].extend([
                {"id": index, "name": package.name,
                 "browser_download_url": f"https://github.com/{REPOSITORY}/releases/download/app-v{VERSION}/{package.name}"},
                {"id": index + 100, "name": f"{package.name}.sig"},
            ])
        release_path.write_text(json.dumps(release), encoding="utf-8")
        merged = root / "merged.json"
        run("assemble", root, minisign, bundle_root=bundle, output=merged, **common)
        run("verify", root, minisign, bundle_root=bundle, output=merged, **common)

        merged_data = json.loads(merged.read_text(encoding="utf-8"))
        del merged_data["platforms"]["windows-x86_64-nsis"]
        merged.write_text(json.dumps(merged_data), encoding="utf-8")
        run("verify", root, minisign, expected=1, bundle_root=bundle, output=merged, **common)
        with appimage.open("ab") as output:
            output.write(b"\x00")
        run("assemble", root, minisign, expected=1, bundle_root=bundle, output=merged, **common)
    print("Linux draft assembly, Windows preservation, and tamper rejection passed.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--minisign", required=True)
    main(parser.parse_args().minisign)
