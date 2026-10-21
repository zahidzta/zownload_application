# 0C-11 — Process death and `.part` recovery (AC-33)

## Device and exact command

The owner-approved, rights-cleared Sintel YouTube single was `https://www.youtube.com/watch?v=eRsGyueVLvQ`. Instrumentation limited the initial transfer to 32K to expose a real `.part`; after Continue it used 256K to allow observation of growth. The physical OnePlus BE2011 (`b1c28e0d`) was Android API 29, `arm64-v8a`, with WebView 155.0.8059.43.

```powershell
$env:JAVA_HOME = 'C:\Users\zahid\AppData\Local\Temp\zownload-0a-10-corretto\jdk21.0.11_10'
$env:ANDROID_SERIAL = 'b1c28e0d'
$env:ZOWNLOAD_ANDROID_LONG_URL = 'https://www.youtube.com/watch?v=eRsGyueVLvQ'
powershell -NoProfile -File scripts/gate-0c/verify.ps1 -Case process-death
```

The exact verifier exited 0 on 2026-10-21. The arm64 debug APK SHA-256 was `28b8462d0a28afbc7d9407e02062d26829a10366620f06952a6b47940da15f24`. The two instrumentation phases used one test each; the first was deliberately terminated with the app and the second reported `OK (1 test)`. Full build, instrumentation, and logcat output is ignored under `work/android/0c-11/`.

## Observed recovery

Rust had persisted item `10c43bb9-1c68-436b-af9f-3e9f1f55a64e` as `downloading`. Instrumentation observed `audio.webm.part` at 15,360 bytes while app PID 4157 and engine child PID 5331 were alive. The host used `adb shell am force-stop com.zownload.app`; direct shell and `run-as` signals to this foreground process were denied on the device. `force-stop` is an abrupt Activity Manager package stop, so this result does not isolate whether Android or parent death terminated the child. After the stop, both observed PIDs were absent. The saved `.part` remained; it had reached 129,626 bytes by the time the stop completed.

On fresh launch, `get_queue` and the Rust SQLite snapshot returned the same item at `paused`. The `.part` stayed at 129,626 bytes for a five-second idle window with no Continue call. The WebView then invoked the contract's `resume_download` command. Kotlin reopened the same item-ID directory and yt-dlp's `--continue --part` path. During the resumed transfer, the same `.part` grew to 259,674 bytes. SHA-256 of its first 8,192 bytes stayed `6fdea32e8a8858239355e4355f00b87675fa003f19cb93da082608b49b21e579` before the stop, after reopen, and after growth.

```text
PREKILL pid=4157 item=10c43bb9-1c68-436b-af9f-3e9f1f55a64e part=audio.webm.part bytes=15360 prefix=6fdea32e8a8858239355e4355f00b87675fa003f19cb93da082608b49b21e579
REOPENED_PAUSED item=10c43bb9-1c68-436b-af9f-3e9f1f55a64e bytes=129626 prefix=6fdea32e8a8858239355e4355f00b87675fa003f19cb93da082608b49b21e579 idleMs=5000
RESUME_INPUT item=10c43bb9-1c68-436b-af9f-3e9f1f55a64e name=audio.webm.part bytes=129626
CONTINUED_PART item=10c43bb9-1c68-436b-af9f-3e9f1f55a64e before=129626 after=259674 prefix=6fdea32e8a8858239355e4355f00b87675fa003f19cb93da082608b49b21e579
```

This proves explicit continuation from the saved private partial file on the tested device; the probe stops after observing growth and does not claim that the resumed MP3 was published or played. `cargo test --manifest-path src-tauri/Cargo.toml android_spike_queue` passed 2/2, `npm run build` passed, Rust formatting and PowerShell parsing passed, and staged whitespace checks passed. The Android native corresponding-source/build-input/notice gap remains an **OPEN RELEASE BLOCKER**. No Android APK or build may be distributed until it is resolved.
