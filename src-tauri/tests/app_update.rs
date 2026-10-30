// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

#![cfg(windows)]

use std::{
    io::{Read, Write},
    net::TcpListener,
    thread,
    time::Duration,
};
use tauri_plugin_updater::UpdaterExt;
use url::Url;

#[test]
fn updater_verifies_local_signed_assets_for_both_installer_targets() {
    for target in ["windows-x86_64-nsis", "windows-x86_64-msi"] {
        let bytes = include_bytes!("../../tests/fixtures/app-updates/update-fixture.bin").to_vec();
        verify_fixture_download(target, bytes).unwrap();
        assert!(verify_fixture_download(target, b"tampered artifact".to_vec()).is_err());
    }
}

fn verify_fixture_download(target: &str, artifact: Vec<u8>) -> Result<(), String> {
    let listener = TcpListener::bind("127.0.0.1:0").map_err(|error| error.to_string())?;
    let address = listener.local_addr().map_err(|error| error.to_string())?;
    let base = format!("http://{address}");
    let base_for_thread = base.clone();
    let signature = include_str!("../../tests/fixtures/app-updates/update-fixture.bin.sig")
        .trim()
        .to_owned();
    let target_for_thread = target.to_owned();
    let server = thread::spawn(move || {
        for _ in 0..2 {
            let (mut stream, _) = listener.accept().unwrap();
            let mut request = Vec::new();
            let mut byte = [0u8; 1];
            while stream.read(&mut byte).unwrap() == 1 {
                request.push(byte[0]);
                if request.ends_with(b"\r\n\r\n") {
                    break;
                }
            }
            let request = String::from_utf8_lossy(&request).into_owned();
            let path = request
                .lines()
                .next()
                .and_then(|line| line.split_whitespace().nth(1))
                .unwrap_or_default()
                .to_owned();
            let body = if path == "/latest.json" {
                let platform = serde_json::json!({
                    "url": format!("{base_for_thread}/{target_for_thread}.bin"),
                    "signature": signature
                });
                serde_json::to_vec(&serde_json::json!({
                    "version": "1.2.0",
                    "platforms": {
                        "windows-x86_64-nsis": platform.clone(),
                        "windows-x86_64-msi": platform
                    }
                }))
                .unwrap()
            } else {
                artifact.clone()
            };
            write!(
                stream,
                "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                body.len()
            )
            .unwrap();
            stream.write_all(&body).unwrap();
        }
    });

    let mut context = tauri::test::mock_context(tauri::test::noop_assets());
    context.config_mut().plugins.0.insert(
        "updater".into(),
        serde_json::json!({
            "pubkey": include_str!("../../tests/fixtures/app-updates/test-key.pub").trim(),
            "endpoints": []
        }),
    );
    let app = tauri::test::mock_builder()
        .plugin(tauri_plugin_updater::Builder::new().build())
        .build(context)
        .map_err(|error| error.to_string())?;
    let updater = app
        .updater_builder()
        .target(target)
        .timeout(Duration::from_secs(5))
        .pubkey(include_str!("../../tests/fixtures/app-updates/test-key.pub").trim())
        .endpoints(vec![
            Url::parse(&format!("{base}/latest.json")).map_err(|error| error.to_string())?
        ])
        .map_err(|error| error.to_string())?
        .build()
        .map_err(|error| error.to_string())?;
    let update = tauri::async_runtime::block_on(updater.check())
        .map_err(|error| error.to_string())?
        .ok_or_else(|| "local stable update was not selected".to_owned())?;
    let result = tauri::async_runtime::block_on(update.download(|_, _| {}, || {}))
        .map(|_| ())
        .map_err(|error| error.to_string());
    server
        .join()
        .map_err(|_| "fixture server panicked".to_owned())?;
    result
}
