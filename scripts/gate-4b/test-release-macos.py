# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 zahidzta

"""Exercise macOS draft assembly, platform preservation, and signature checks."""

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[2]
VERIFIER = ROOT / "scripts/gate-4b/release-macos.py"
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
        raise AssertionError(
            f"{stage} returned {result.returncode}: {result.stdout}{result.stderr[-1000:]}"
        )


def main(minisign):
    with tempfile.TemporaryDirectory(prefix="zownload-4b-macos-test-") as temporary:
        root = Path(temporary)
        signatures = root / "signatures"
        signatures.mkdir()
        bundle = root / "bundle"
        bundle.mkdir()
        signature = (FIXTURES / "update-fixture.bin.sig").read_text(encoding="utf-8").strip()
        fixture = FIXTURES / "update-fixture.bin"
        config = {
            "version": VERSION,
            "plugins": {"updater": {"pubkey": (FIXTURES / "test-key.pub").read_text().strip()}},
        }
        (root / "config.json").write_text(json.dumps(config), encoding="utf-8")

        windows_names = [
            f"Zownload_{VERSION}_x64-setup.exe",
            f"Zownload_{VERSION}_x64_en-US.msi",
        ]
        linux_names = [
            f"Zownload_{VERSION}_amd64.AppImage",
            f"Zownload_{VERSION}_amd64.deb",
        ]
        base_assets = []
        package_ids = {}
        for asset_id, name in enumerate(windows_names + linux_names, 101):
            data_path = root / name
            shutil.copyfile(fixture, data_path)
            base_assets.append({
                "id": asset_id,
                "name": name,
                "browser_download_url":
                    f"https://github.com/{REPOSITORY}/releases/download/app-v{VERSION}/{name}",
            })
            package_ids[name] = asset_id
            signature_path = signatures / f"{name}.sig"
            signature_path.write_text(signature, encoding="utf-8")
            base_assets.append({"id": asset_id + 100, "name": signature_path.name})
        base_assets.append({"id": 999, "name": "latest.json"})

        platforms = {}
        for key, package in (
            ("windows-x86_64", windows_names[1]),
            ("windows-x86_64-msi", windows_names[1]),
            ("windows-x86_64-nsis", windows_names[0]),
            ("linux-x86_64", linux_names[0]),
        ):
            platforms[key] = {
                "signature": signature,
                "url": f"https://api.github.com/repos/{REPOSITORY}/releases/assets/{package_ids[package]}",
            }
        baseline = {"version": VERSION, "notes": "preserve these notes", "platforms": platforms}
        latest_path = root / "latest.json"
        latest_path.write_text(json.dumps(baseline), encoding="utf-8")
        release = {"draft": True, "tag_name": f"app-v{VERSION}", "assets": base_assets}
        release_path = root / "release.json"
        release_path.write_text(json.dumps(release), encoding="utf-8")
        common = {"release": release_path, "latest": latest_path, "signatures": signatures}
        run("preflight", root, minisign, **common)

        for architecture in ("aarch64", "x86_64"):
            dmg = f"Zownload_{VERSION}_{architecture}.dmg"
            archive = f"Zownload_{VERSION}_{architecture}.app.tar.gz"
            signature_name = f"{archive}.sig"
            (bundle / dmg).write_bytes(b"macOS disk image fixture")
            shutil.copyfile(fixture, bundle / archive)
            (bundle / signature_name).write_text(signature, encoding="utf-8")

        for architecture in ("aarch64", "x86_64"):
            architecture_bundle = root / f"bundle-{architecture}"
            architecture_bundle.mkdir()
            prefix = f"Zownload_{VERSION}_{architecture}."
            for path in bundle.iterdir():
                if path.name.startswith(prefix):
                    shutil.copyfile(path, architecture_bundle / path.name)
            run("signed", root, minisign, bundle_root=architecture_bundle,
                version=VERSION, architecture=architecture)

        next_asset_id = 1000
        for path in sorted(bundle.iterdir()):
            data = path.read_bytes()
            release["assets"].append({
                "id": next_asset_id,
                "name": path.name,
                "size": len(data),
                "digest": f"sha256:{hashlib.sha256(data).hexdigest()}",
                "browser_download_url":
                    f"https://github.com/{REPOSITORY}/releases/download/app-v{VERSION}/{path.name}",
            })
            next_asset_id += 1
        release_path.write_text(json.dumps(release), encoding="utf-8")
        merged = root / "merged.json"
        run("assemble", root, minisign, bundle_root=bundle, output=merged, **common)
        run("verify", root, minisign, bundle_root=bundle, output=merged, **common)
        run("metadata", root, minisign, bundle_root=bundle, output=merged, **common)

        wrong_metadata = json.loads(merged.read_text(encoding="utf-8"))
        del wrong_metadata["platforms"]["windows-x86_64-nsis"]
        wrong_path = root / "wrong-latest.json"
        wrong_path.write_text(json.dumps(wrong_metadata), encoding="utf-8")
        run("verify", root, minisign, expected=1, bundle_root=bundle,
            output=wrong_path, **common)

        release["assets"].append({"id": 2000, "name": "unexpected.pkg"})
        release_path.write_text(json.dumps(release), encoding="utf-8")
        run("verify", root, minisign, expected=1, bundle_root=bundle,
            output=merged, **common)
        release["assets"].pop()
        release_path.write_text(json.dumps(release), encoding="utf-8")

        archive = bundle / f"Zownload_{VERSION}_aarch64.app.tar.gz"
        with archive.open("ab") as output:
            output.write(b"\x00")
        run("signed", root, minisign, expected=1, bundle_root=bundle)
    print("macOS draft assembly, Windows/Linux preservation, asset allowlist, and tamper rejection passed.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--minisign", required=True)
    main(parser.parse_args().minisign)
