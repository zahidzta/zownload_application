# 0C-14 — verified yt-dlp update and rollback

## Pinned inputs

| Role | Version and EJS | SHA-256 | Source |
|---|---|---|---|
| Bundled fallback | yt-dlp `2026.08.19`, EJS `0.8.0` | `1fa6733c37ea6fb51c99ad8fe785e7b7e5f3246c9b980230329d4fb72ed8d4d6` | [Gate 0C-05 package proof](quickjs.md) |
| Update candidate | yt-dlp stable `2026.10.21`, EJS `0.8.0` | `b7af77f686e95f7845ce8d09d21957718febb8b48b30555adb9dd2292ad7bf14` | [Immutable release](https://github.com/yt-dlp/yt-dlp/releases/tag/2026.10.21), [Unix zipapp](https://github.com/yt-dlp/yt-dlp/releases/download/2026.10.21/yt-dlp), [published SHA2-256SUMS](https://github.com/yt-dlp/yt-dlp/releases/download/2026.10.21/SHA2-256SUMS), [tagged EJS pin](https://github.com/yt-dlp/yt-dlp/blob/2026.10.21/pyproject.toml) |

The candidate zipapp was downloaded from the release, its SHA-256 matched the
published checksum entry and the GitHub release API asset digest, and inspection
found `yt_dlp/version.py` = `2026.10.21` and
`yt_dlp_ejs/_version.py` = `0.8.0`. The release zipapp reports commit
`8cdf4fea48ecf4064387375301d7f294ebdb17c1` in its version module.
No Android APK or engine binary was uploaded or published.

## Custom path

`VerifiedYtDlpUpdate` downloads the fixed stable release over HTTPS into an
app-private staging file with time and size limits. It checks the embedded
SHA-256, both package identities, and `--version` through the Android Python
runtime before an atomic same-directory rename. An accepted-version marker
records the candidate only after the archive rename. At startup, an incomplete
or mismatched marker restores the hash-checked bundled baseline. A later
reported failure re-copies that baseline and executes its `--version` check.
The candidate and baseline both remain in the same app-private yt-dlp path
used by the adapter. The tagged youtubedl-android updater is never called.

A process-wide gate rejects updates while the adapter analyzes or downloads,
including the interval between the Rust-triggered plugin call and the worker's
`execute()`. It also refuses new jobs during an update. Kotlin holds only this
temporary swap guard; Rust remains the queue owner. The gate and rollback path
do not add a second queue.

## Physical device run

- Exact command: `powershell -NoProfile -File scripts/gate-0c/verify.ps1 -Case update-rollback`, with `ANDROID_SERIAL=b1c28e0d` and `JAVA_HOME` set to pinned Corretto `21.0.11.10.1`.
- Device: physical OnePlus BE2011, Android API 29, `arm64-v8a`, serial `b1c28e0d`.
- Instrumentation: `YtDlpUpdateDeviceTest#verifiedStableUpdateRejectsUnsafeSwapsAndRollsBack`, `OK (1 test)`, exit code `-1`. Full local build, test, and logcat output is ignored under `work/android/0c-14/`.
- App debug APK SHA-256: `0a5c1c807e08f9bd20f215e9b1058814dcc7da0d8444780d428a16c663f9fc97`.

Relevant device log excerpts (timestamps are device local time):

```text
17:10:17 BASELINE version=2026.08.19 hash=1fa6733c37ea6fb51c99ad8fe785e7b7e5f3246c9b980230329d4fb72ed8d4d6
17:10:18 ACTIVE_JOB_REJECTED hash=1fa6733c37ea6fb51c99ad8fe785e7b7e5f3246c9b980230329d4fb72ed8d4d6
17:10:18 BAD_CANDIDATE_REJECTED hash=1fa6733c37ea6fb51c99ad8fe785e7b7e5f3246c9b980230329d4fb72ed8d4d6
17:10:25 CANDIDATE_VERIFIED version=2026.10.21 ejs=0.8.0 hash=b7af77f686e95f7845ce8d09d21957718febb8b48b30555adb9dd2292ad7bf14
17:10:30 UPDATE_OK version=2026.10.21 ejs=0.8.0 hash=b7af77f686e95f7845ce8d09d21957718febb8b48b30555adb9dd2292ad7bf14
17:10:59 RUNTIME [debug] yt-dlp version stable@2026.10.21 from yt-dlp/yt-dlp [8cdf4fea4] (zip)
17:10:59 RUNTIME [debug] Optional libraries: Cryptodome-3.23.0, mutagen-1.47.0, sqlite3-3.50.4, yt_dlp_ejs-0.8.0
17:10:59 POST_ACCEPT_FAILURE reason=injected post-acceptance failure
17:11:04 ROLLBACK_OK version=2026.08.19 hash=1fa6733c37ea6fb51c99ad8fe785e7b7e5f3246c9b980230329d4fb72ed8d4d6
17:11:32 RECOVERY_OK version=2026.08.19 hash=1fa6733c37ea6fb51c99ad8fe785e7b7e5f3246c9b980230329d4fb72ed8d4d6
```

The runtime check started the accepted zipapp through youtubedl-android,
reported the selected EJS, and then the injected post-acceptance failure
restored and executed the baseline. The bad candidate and active-job probes
left the baseline hash unchanged. The probe used a reserved engine job rather
than a concurrent media transfer, and tested orderly rollback rather than a
process kill during the rename. It did not download media with the new yt-dlp
version. Android native corresponding-source, build-input, and notice
provenance remains an **OPEN RELEASE BLOCKER**; this is local feasibility only.

The first local invocation failed before Kotlin compilation because this
shell's pre-existing `JAVA_HOME` pointed to an unusable Android Studio JBR.
Selecting the already downloaded, pinned Corretto JDK resolved that setup
error; the exact verifier then exited `0`.
