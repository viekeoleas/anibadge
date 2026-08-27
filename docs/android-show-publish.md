# Android ZSHOW publish flow

The Flutter application discovers the Waveshare 31523 over BLE, requests a
temporary Wi-Fi session, and publishes an already compiled `.zshow` package.
The board does not keep an access point running between operations.

## User-visible stages

1. **Подключение** — Android discovers the BLE service, requests a versioned
   publish session, binds to the returned temporary Wi-Fi network, and checks
   that the firmware is reachable.
2. **Передача** — the package is streamed as a multipart POST; both displays
   show determinate progress. The board redraws only at two-percent increments.
3. **Проверка** — after the request body is sent, the board checks the ZSHOW
   structure, compatibility, frame metadata, JPEG headers, and both CRC32
   values.
4. **Установка** — the validated PSRAM package is written sequentially to the
   dedicated raw-flash partition and committed. The app polls the player status
   instead of treating HTTP 200 as proof of playback.
5. **Готово** — the board reports `playing`; Android releases the BLE session,
   unbinds the temporary network, and the board disables Wi-Fi.

The selected file is retained in memory after a failure, so the same publish
can be retried without reopening the picker. A failed or abandoned session
expires on the board after 180 seconds and leaves BLE advertising available.

## HTTP boundary

Upload:

```text
POST /show/upload?name=current.zshow&size=<exact package bytes>
Content-Type: multipart/form-data; boundary=...
```

Successful response:

```json
{"ok":true,"validation":"ok","installed":true}
```

A rejected upload returns HTTP 422 and a stable firmware error code, for
example `payload-crc`, `unsupported-version`, `target-board`, `storage-full`,
or `package-size`. The app turns these into readable Russian messages.

Activation status:

```text
GET /show/status
```

Example response:

```json
{"state":"playing","installed":true}
```

Only `playing` completes publication. The previous package is removed when a
replacement upload starts. An interrupted upload is discarded, leaves the
built-in fallback active, and can be retried.

Media cleanup:

```text
POST /show/clear
```

Successful response:

```json
{"ok":true,"installed":false}
```

This stops playback, invalidates the raw show partition, and removes uploaded
legacy GIF files under the board's `/media` directory. Firmware, persistent
settings, and projects stored on the phone are not removed. The board returns
to its built-in startup screen after cleanup.

## Verification

`app/test/show_publisher_test.dart` exercises the transport boundary with a
fake device for success, checksum rejection, timeout, and retry. Package header
inspection and the staged UI have separate tests.

Run:

```powershell
cd app
flutter analyze
flutter test
flutter pub get
flutter build apk --release --split-per-abi
cd ..
.\tools\verify_android_release_plugins.ps1
```

Do not use `--no-pub` for a release after running integration tests: it can
leave the test plugin registrant in place or skip generation of the production
registrant. The verification script rejects an APK where required Android
plugins are missing or removed by R8.

The installable arm64 release artifact is
`artifacts/Znachok-Editor-v3.9.0-arm64-release.apk`. It is an optimized release
build signed with the current development key; production signing remains a
release-engineering task.
