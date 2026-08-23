#!/usr/bin/env python3
"""Build and validate Znachok show packages without third-party dependencies."""

from __future__ import annotations

import argparse
import dataclasses
import pathlib
import struct
import sys
import zlib


MAGIC = b"ZSHOWV1\0"
FORMAT_VERSION = 1
HEADER_SIZE = 64
PLAYER_API_VERSION = 1
TARGET_WAVESHARE_31523 = 1
CODEC_BASELINE_JPEG = 1
FLAG_LOOP = 1
MAX_PACKAGE_BYTES = 20 * 1024 * 1024
MAX_FRAME_BYTES = 212 * 1024
MAX_FRAMES = 20_000
WIDTH = 800
HEIGHT = 800

HEADER = struct.Struct("<8sHHIHHHHIIIIIIIHHII")
FRAME = struct.Struct("<IIII")
assert HEADER.size == HEADER_SIZE
assert FRAME.size == 16


class PackageError(ValueError):
    pass


@dataclasses.dataclass(frozen=True)
class FrameInfo:
    offset: int
    size: int
    duration_us: int
    flags: int


@dataclasses.dataclass(frozen=True)
class PackageInfo:
    version: int
    width: int
    height: int
    fps: int
    flags: int
    player_api: int
    target_board: int
    codec: int
    frames: tuple[FrameInfo, ...]
    payload_size: int


def _crc32(data: bytes) -> int:
    return zlib.crc32(data) & 0xFFFFFFFF


def jpeg_dimensions(data: bytes) -> tuple[int, int]:
    if len(data) < 4 or data[:2] != b"\xff\xd8":
        raise PackageError("frame is not JPEG")
    cursor = 2
    while cursor + 4 <= len(data):
        if data[cursor] != 0xFF:
            raise PackageError("invalid JPEG marker")
        while cursor < len(data) and data[cursor] == 0xFF:
            cursor += 1
        if cursor >= len(data):
            break
        marker = data[cursor]
        cursor += 1
        if marker in (0x01, 0xD8, 0xD9):
            continue
        if cursor + 2 > len(data):
            break
        segment_size = int.from_bytes(data[cursor : cursor + 2], "big")
        if segment_size < 2 or cursor + segment_size > len(data):
            raise PackageError("truncated JPEG segment")
        if marker == 0xC0:
            if segment_size < 8:
                raise PackageError("invalid JPEG SOF0")
            height = int.from_bytes(data[cursor + 3 : cursor + 5], "big")
            width = int.from_bytes(data[cursor + 5 : cursor + 7], "big")
            return width, height
        if marker in {
            0xC1,
            0xC2,
            0xC3,
            0xC5,
            0xC6,
            0xC7,
            0xC9,
            0xCA,
            0xCB,
            0xCD,
            0xCE,
            0xCF,
        }:
            raise PackageError("only baseline JPEG (SOF0) is supported")
        cursor += segment_size
    raise PackageError("JPEG dimensions not found")


def build_package(frame_data: list[bytes], fps: int = 60) -> bytes:
    if not 1 <= fps <= 60:
        raise PackageError("fps must be in 1..60")
    if not frame_data or len(frame_data) > MAX_FRAMES:
        raise PackageError("invalid frame count")

    duration_us = round(1_000_000 / fps)
    payload_parts: list[bytes] = []
    entries: list[bytes] = []
    payload_cursor = 0
    for number, jpeg in enumerate(frame_data):
        if not jpeg or len(jpeg) > MAX_FRAME_BYTES:
            raise PackageError(f"frame {number} exceeds {MAX_FRAME_BYTES} bytes")
        if jpeg_dimensions(jpeg) != (WIDTH, HEIGHT):
            raise PackageError(f"frame {number} must be {WIDTH}x{HEIGHT}")
        entries.append(FRAME.pack(payload_cursor, len(jpeg), duration_us, 0))
        payload_parts.append(jpeg)
        payload_cursor += len(jpeg)

    index = b"".join(entries)
    payload = b"".join(payload_parts)
    payload_offset = HEADER_SIZE + len(index)
    package_size = payload_offset + len(payload)
    if package_size > MAX_PACKAGE_BYTES:
        raise PackageError("package exceeds maximum size")

    fields = (
        MAGIC,
        FORMAT_VERSION,
        HEADER_SIZE,
        package_size,
        WIDTH,
        HEIGHT,
        fps,
        FLAG_LOOP,
        len(frame_data),
        HEADER_SIZE,
        len(index),
        payload_offset,
        len(payload),
        0,
        _crc32(payload),
        PLAYER_API_VERSION,
        TARGET_WAVESHARE_31523,
        CODEC_BASELINE_JPEG,
        0,
    )
    header_without_crc = HEADER.pack(*fields)
    manifest_crc = _crc32(header_without_crc + index)
    fields = fields[:13] + (manifest_crc,) + fields[14:]
    return HEADER.pack(*fields) + index + payload


def validate_package(data: bytes, *, verify_jpeg: bool = True) -> PackageInfo:
    if len(data) < HEADER_SIZE:
        raise PackageError("truncated header")
    values = list(HEADER.unpack_from(data))
    (
        magic,
        version,
        header_size,
        package_size,
        width,
        height,
        fps,
        flags,
        frame_count,
        index_offset,
        index_size,
        payload_offset,
        payload_size,
        manifest_crc,
        payload_crc,
        player_api,
        target_board,
        codec,
        reserved,
    ) = values

    if magic != MAGIC:
        raise PackageError("bad magic")
    if version != FORMAT_VERSION:
        raise PackageError(f"unsupported format version {version}")
    if header_size != HEADER_SIZE:
        raise PackageError("unsupported header size")
    if package_size != len(data) or package_size > MAX_PACKAGE_BYTES:
        raise PackageError("package size mismatch")
    if (width, height) != (WIDTH, HEIGHT):
        raise PackageError("unsupported canvas")
    if not 1 <= fps <= 60:
        raise PackageError("unsupported fps")
    if flags != FLAG_LOOP:
        raise PackageError("unsupported package flags")
    if not 1 <= frame_count <= MAX_FRAMES:
        raise PackageError("invalid frame count")
    if index_offset != HEADER_SIZE or index_size != frame_count * FRAME.size:
        raise PackageError("invalid frame index")
    if payload_offset != index_offset + index_size:
        raise PackageError("invalid payload offset")
    if payload_size != package_size - payload_offset:
        raise PackageError("invalid payload size")
    if player_api > PLAYER_API_VERSION:
        raise PackageError("player API is too old")
    if target_board != TARGET_WAVESHARE_31523:
        raise PackageError("package targets another board")
    if codec != CODEC_BASELINE_JPEG:
        raise PackageError("unsupported codec")
    if reserved != 0:
        raise PackageError("reserved field must be zero")

    header_for_crc = bytearray(data[:HEADER_SIZE])
    struct.pack_into("<I", header_for_crc, 44, 0)
    index = data[index_offset:payload_offset]
    if _crc32(bytes(header_for_crc) + index) != manifest_crc:
        raise PackageError("manifest CRC mismatch")
    payload = data[payload_offset:]
    if _crc32(payload) != payload_crc:
        raise PackageError("payload CRC mismatch")

    frames: list[FrameInfo] = []
    expected_offset = 0
    for number in range(frame_count):
        entry = FrameInfo(*FRAME.unpack_from(index, number * FRAME.size))
        if entry.offset != expected_offset:
            raise PackageError(f"frame {number} is not contiguous")
        if not 0 < entry.size <= MAX_FRAME_BYTES:
            raise PackageError(f"frame {number} has invalid size")
        if not 1_000 <= entry.duration_us <= 10_000_000:
            raise PackageError(f"frame {number} has invalid duration")
        if entry.flags != 0 or entry.offset + entry.size > payload_size:
            raise PackageError(f"frame {number} has invalid metadata")
        jpeg = payload[entry.offset : entry.offset + entry.size]
        if verify_jpeg and jpeg_dimensions(jpeg) != (WIDTH, HEIGHT):
            raise PackageError(f"frame {number} has invalid JPEG dimensions")
        expected_offset += entry.size
        frames.append(entry)
    if expected_offset != payload_size:
        raise PackageError("unreferenced payload bytes")

    return PackageInfo(
        version=version,
        width=width,
        height=height,
        fps=fps,
        flags=flags,
        player_api=player_api,
        target_board=target_board,
        codec=codec,
        frames=tuple(frames),
        payload_size=payload_size,
    )


def _command_pack(args: argparse.Namespace) -> None:
    frames = [pathlib.Path(path).read_bytes() for path in args.frames]
    package = build_package(frames, args.fps)
    output = pathlib.Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(package)
    info = validate_package(package)
    print(
        f"wrote {output}: {len(info.frames)} frames, "
        f"{info.payload_size} payload bytes, {info.fps} FPS"
    )


def _command_validate(args: argparse.Namespace) -> None:
    path = pathlib.Path(args.package)
    info = validate_package(path.read_bytes())
    print(
        f"OK {path}: ZSHOW v{info.version}, {info.width}x{info.height}, "
        f"{len(info.frames)} frames, {info.fps} FPS, "
        f"{info.payload_size} payload bytes"
    )


def _command_embed(args: argparse.Namespace) -> None:
    package = pathlib.Path(args.package).read_bytes()
    validate_package(package)
    lines = [
        "// Generated by tools/zshow.py embed. Do not edit.",
        '#include "p4_show_contract_fixture.h"',
        "",
        "namespace p4showcontract {",
        "alignas(16) const uint8_t kGoldenPackage[] = {",
    ]
    for offset in range(0, len(package), 16):
        values = ", ".join(f"0x{value:02x}" for value in package[offset : offset + 16])
        lines.append(f"    {values},")
    lines.extend(
        [
            "};",
            "const size_t kGoldenPackageSize = sizeof(kGoldenPackage);",
            "}  // namespace p4showcontract",
            "",
        ]
    )
    output = pathlib.Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(lines), encoding="utf-8")
    print(f"embedded {len(package)} bytes into {output}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="zshow")
    subparsers = parser.add_subparsers(required=True)
    pack = subparsers.add_parser("pack", help="create a ZSHOW v1 package")
    pack.add_argument("-o", "--output", required=True)
    pack.add_argument("--fps", type=int, default=60)
    pack.add_argument("frames", nargs="+")
    pack.set_defaults(command=_command_pack)
    validate = subparsers.add_parser("validate", help="validate a package")
    validate.add_argument("package")
    validate.set_defaults(command=_command_validate)
    embed = subparsers.add_parser("embed", help="embed a valid package in C++")
    embed.add_argument("package")
    embed.add_argument("-o", "--output", required=True)
    embed.set_defaults(command=_command_embed)
    args = parser.parse_args(argv)
    try:
        args.command(args)
    except (OSError, PackageError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
