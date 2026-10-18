use serde_json::{json, Value};
use zownload_lib::contract::{DownloadRequest, Format, Progress, Quality};

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
    });

    assert_eq!(rust_values, fixture);
}
