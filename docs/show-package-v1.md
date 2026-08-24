# ZSHOW v1 package contract

ZSHOW is the versioned publish format shared by the host compiler and the
Waveshare 31523 firmware. Version 1 is a looping sequence of baseline JPEG
frames. All integers are unsigned little-endian values.

## Limits and compatibility

- canvas: exactly 800 x 800;
- codec: baseline JPEG / SOF0 (`codec = 1`);
- rate: 1–60 FPS, with an explicit duration on every frame;
- package size: at most 20 MiB;
- frame size: at most 212 KiB (180 KiB is the production target);
- frame count: 1–20,000;
- player API: package value must be no newer than firmware API 1;
- target board: Waveshare 31523 (`target_board = 1`);
- playback flag: looping is mandatory (`flags = 1`).

## Binary layout

The package is `header + frame index + JPEG payload`. The 64-byte header is:

| Offset | Type | Field | v1 value / meaning |
| ---: | --- | --- | --- |
| 0 | `char[8]` | magic | `ZSHOWV1\0` |
| 8 | `u16` | version | `1` |
| 10 | `u16` | header size | `64` |
| 12 | `u32` | package size | exact uploaded byte count |
| 16 | `u16` | width | `800` |
| 18 | `u16` | height | `800` |
| 20 | `u16` | FPS | declared sequence rate |
| 22 | `u16` | flags | `1` = loop |
| 24 | `u32` | frame count | number of index entries |
| 28 | `u32` | index offset | `64` |
| 32 | `u32` | index size | frame count × 16 |
| 36 | `u32` | payload offset | byte after the index |
| 40 | `u32` | payload size | all concatenated JPEG bytes |
| 44 | `u32` | manifest CRC32 | header with this field zeroed + index |
| 48 | `u32` | payload CRC32 | JPEG payload |
| 52 | `u16` | player API | `1` |
| 54 | `u16` | target board | `1` = Waveshare 31523 |
| 56 | `u32` | codec | `1` = baseline JPEG |
| 60 | `u32` | reserved | `0` |

Each 16-byte index entry is `payload_offset:u32`, `jpeg_size:u32`,
`duration_us:u32`, `flags:u32`. Frame offsets are relative to the payload and
must form one contiguous range with no gaps or unreferenced trailing bytes.
Frame flags are zero in v1.

Both checksums use the standard CRC-32 algorithm exposed by Python's
`zlib.crc32`. Structural and compatibility checks run before either the player
or the installed package is changed.

## Host commands

Create a package from already prepared 800 x 800 baseline JPEG frames, in
playback order:

```powershell
python tools/zshow.py pack --fps 60 -o show.zshow frame-001.jpg frame-002.jpg
```

Validate a package without a connected board:

```powershell
python tools/zshow.py validate show.zshow
python -m unittest discover -s test -p 'test_*.py' -v
```

The checked-in cross-platform fixture is `test/fixtures/golden-v1.zshow`.
`embed` converts it to the C++ data used only by the hardware contract-test
environment.

## Upload and boot behavior

The firmware accepts a multipart POST at
`/show/upload?name=current.zshow&size=<exact-byte-count>`. When PSRAM has room
(the player is stopped during upload, so it normally does) the package streams
directly into a PSRAM buffer, is validated in RAM, and only then is written to
`/media/current.zshow` in one sequential pass and handed to the player without
a read-back. Without PSRAM headroom the firmware falls back to streaming into
a temporary LittleFS file and validating the completed file. In both modes a
rejected or interrupted upload leaves the previous show intact.

On boot, the runtime tries the installed ZSHOW first, then the legacy GIF. A
valid ZSHOW starts automatically and loops forever. If no playable package
exists, or playback later fails, the built-in `SAFE MODE / NO VALID SHOW`
screen is displayed. Invalid, truncated, corrupt, wrong-board, wrong-codec, or
unsupported-version packages are never passed to the JPEG player.

## Hardware proof

The `esp32p4-contract-test` environment validates truncated, corrupted, and v2
packages in both the parser and player boundary, verifies that corrupt streamed
data cannot replace the installed show, installs the golden v1 fixture, then
reboots. On the next boot it reloads the file, checks byte identity, and starts
the looping show. The same saved package was then booted by the normal
`esp32p4` release firmware.

Final board telemetry on 2026-08-22 showed alternating two-frame playback at
59.76–60.26 FPS over two-second sampling windows, zero timeline resyncs, about
6.58 ms hardware JPEG decode time, and stable free PSRAM of 30,858,464 bytes.
