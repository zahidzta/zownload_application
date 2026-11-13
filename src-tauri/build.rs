// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta
use sha2::{Digest, Sha256};
use std::{env, fs, path::Path};

const WINDOWS_ENGINE_HASHES: [(&str, &str, &str); 2] = [
    (
        "ffmpeg.exe",
        "ZOWNLOAD_BASELINE_FFMPEG_SHA256",
        "fa050630ddf5b7c3303d8dab5e5a42e7023547fb78ec9b90b5be0a4f788a7e66",
    ),
    (
        "qjs.exe",
        "ZOWNLOAD_BASELINE_QUICKJS_SHA256",
        "bec67f8f87fa22958d3ab8be5508088116b8bff90032323d82c94545e1698b83",
    ),
];

const MACOS_YT_DLP_SHA256: &str =
    "0f192b7ec147ab6288885d6351d9ab67367640029b4377576ef46dd79cf7b202";
const MACOS_QUICKJS_HASHES: [(&str, &str); 2] = [
    (
        "x86_64",
        "554102a8a9c0d0c5e24cd138ad7a790f330fd926310c01009265589a446ef90a",
    ),
    (
        "aarch64",
        "fba79a316a53ed58a17709a39c173218f8bc825831094b6033ce0510a713bb43",
    ),
];

// Embed hashes from the staged files because rebuilt FFmpeg output can vary between runs.
fn emit_windows_engine_hashes() {
    if env::var("CARGO_CFG_TARGET_OS").as_deref() != Ok("windows") {
        return;
    }

    let resources = Path::new(env!("CARGO_MANIFEST_DIR")).join("resources/windows-engine");
    let staged = WINDOWS_ENGINE_HASHES
        .iter()
        .map(|(filename, _, _)| resources.join(filename))
        .collect::<Vec<_>>();
    let present = staged.iter().filter(|path| path.is_file()).count();
    let release = env::var("PROFILE").as_deref() == Ok("release");

    if (present != 0 && present != staged.len()) || (release && present != staged.len()) {
        panic!("Windows engine resources must be fully staged before a release build");
    }

    let all_present = present == staged.len();
    for ((_, variable, fallback), path) in WINDOWS_ENGINE_HASHES.iter().zip(staged) {
        println!("cargo:rerun-if-changed={}", path.display());
        let hash = if all_present {
            let bytes = fs::read(&path).unwrap_or_else(|error| {
                panic!(
                    "could not read Windows engine resource {}: {error}",
                    path.display()
                )
            });
            format!("{:x}", Sha256::digest(bytes))
        } else {
            (*fallback).to_owned()
        };
        println!("cargo:rustc-env={variable}={hash}");
    }
}

// The macOS FFmpeg build is produced natively on each runner. Embed the hashes
// of those staged outputs, while keeping normal unbundled debug builds possible.
fn emit_macos_engine_hashes() {
    if env::var("CARGO_CFG_TARGET_OS").as_deref() != Ok("macos") {
        return;
    }

    let arch = env::var("CARGO_CFG_TARGET_ARCH").expect("Cargo target architecture missing");
    let expected_qjs = MACOS_QUICKJS_HASHES
        .iter()
        .find_map(|(target, hash)| (*target == arch).then_some(*hash))
        .unwrap_or_else(|| panic!("unsupported macOS engine architecture: {arch}"));
    let resources = Path::new(env!("CARGO_MANIFEST_DIR")).join("resources/macos-engine");
    let files = ["yt-dlp", "ffmpeg", "ffprobe", "qjs"].map(|name| resources.join(name));
    let present = files.iter().filter(|path| path.is_file()).count();
    let release = env::var("PROFILE").as_deref() == Ok("release");

    if (present != 0 && present != files.len()) || (release && present != files.len()) {
        panic!("macOS engine resources must be fully staged before a release build");
    }

    let hashes = if present == files.len() {
        let hashes = files
            .iter()
            .map(|path| {
                println!("cargo:rerun-if-changed={}", path.display());
                let bytes = fs::read(path).unwrap_or_else(|error| {
                    panic!(
                        "could not read macOS engine resource {}: {error}",
                        path.display()
                    )
                });
                format!("{:x}", Sha256::digest(bytes))
            })
            .collect::<Vec<_>>();
        if hashes[0] != MACOS_YT_DLP_SHA256 {
            panic!("staged macOS yt-dlp does not match its pinned release hash");
        }
        if hashes[3] != expected_qjs {
            panic!("staged macOS QuickJS does not match the Gate 0B build hash for {arch}");
        }
        [hashes[1].clone(), hashes[2].clone(), hashes[3].clone()]
    } else {
        // Without staged binaries a debug build cannot bootstrap an engine;
        // these values are never accepted against missing resources.
        ["0".repeat(64), "0".repeat(64), expected_qjs.to_owned()]
    };

    for (name, hash) in [
        ("ZOWNLOAD_BASELINE_FFMPEG_SHA256", hashes[0].as_str()),
        ("ZOWNLOAD_BASELINE_FFPROBE_SHA256", hashes[1].as_str()),
        ("ZOWNLOAD_BASELINE_QUICKJS_SHA256", hashes[2].as_str()),
    ] {
        println!("cargo:rustc-env={name}={hash}");
    }
}

fn main() {
    emit_windows_engine_hashes();
    emit_macos_engine_hashes();
    tauri_build::build();
    #[cfg(windows)]
    {
        // Cargo test binaries lack the app bundle manifest needed by Windows dialogs.
        let manifest =
            std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("windows-tests.manifest");
        println!("cargo:rustc-link-arg-tests=/MANIFEST:EMBED");
        println!(
            "cargo:rustc-link-arg-tests=/MANIFESTINPUT:{}",
            manifest.display()
        );
    }
}
