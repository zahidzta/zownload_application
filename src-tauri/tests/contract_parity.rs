// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta
use serde_json::{json, Value};
use zownload_lib::contract::{
    AnalyzeResult, AudioEstimateQuality, DownloadRequest, Format, Progress, Quality,
    SingleEstimate, VideoEstimateQuality,
};

#[test]
fn rust_serialization_matches_shared_json_fixture() {
    // The contract module's own tests read this same file through their fixed path.
    let fixture: Value = serde_json::from_str(include_str!("../../tests/contract-fixtures.json"))
        .expect("shared fixture should be valid JSON");

    let rust_values = json!({
        "downloadRequest": DownloadRequest {
            url: "https://example.com/media".to_string(),
            format: Format::Mp3,
            quality: Quality::Audio { bitrate: 320 },
            is_playlist: false,
        },
        "playlistProgress": Progress::Playlist {
            done: 2,
            failed: 1,
            total: 5,
            current_title: Some("Example".to_string()),
            current_percent: 42.5,
        },
        "singleAnalyzeResult": AnalyzeResult::Single {
            url: "https://example.com/media".to_string(),
            title: "Example".to_string(),
            author: "Uploader".to_string(),
            thumbnail: None,
            duration_sec: 60,
            site: "Example".to_string(),
            video_heights: vec![720],
            audio_output_bitrates: vec![320, 256, 192, 128],
            estimates: Some(vec![
                SingleEstimate::Mp3 {
                    quality: AudioEstimateQuality::Audio { bitrate: 320 },
                    estimated_bytes: 2_400_000,
                },
                SingleEstimate::Mp4 {
                    quality: VideoEstimateQuality::Video { height: 720 },
                    estimated_bytes: 8_000_000,
                },
            ]),
        },
    });

    assert_eq!(rust_values, fixture);
}
