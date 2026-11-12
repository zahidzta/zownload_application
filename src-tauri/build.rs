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

fn main() {
    emit_windows_engine_hashes();
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
