from __future__ import annotations

import pathlib
import struct
import sys
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

import zshow  # noqa: E402


FIXTURES = ROOT / "test" / "fixtures"
GOLDEN = FIXTURES / "golden-v1.zshow"
FRAMES = FIXTURES / "zshow_frames"


class ZshowContractTests(unittest.TestCase):
    def test_golden_package_is_valid_and_deterministic(self) -> None:
        golden = GOLDEN.read_bytes()
        info = zshow.validate_package(golden)
        self.assertEqual(info.version, 1)
        self.assertEqual((info.width, info.height), (800, 800))
        self.assertEqual(info.fps, 60)
        self.assertEqual(len(info.frames), 2)
        rebuilt = zshow.build_package(
            [
                (FRAMES / "graphic_a.jpg").read_bytes(),
                (FRAMES / "graphic_b.jpg").read_bytes(),
            ],
            fps=60,
        )
        self.assertEqual(rebuilt, golden)

    def test_corrupt_payload_is_rejected(self) -> None:
        package = bytearray(GOLDEN.read_bytes())
        package[-17] ^= 0x80
        with self.assertRaisesRegex(zshow.PackageError, "payload CRC"):
            zshow.validate_package(bytes(package))

    def test_truncated_package_is_rejected(self) -> None:
        with self.assertRaisesRegex(zshow.PackageError, "package size"):
            zshow.validate_package(GOLDEN.read_bytes()[:-31])

    def test_unsupported_version_is_rejected_before_playback(self) -> None:
        package = bytearray(GOLDEN.read_bytes())
        struct.pack_into("<H", package, 8, 2)
        with self.assertRaisesRegex(zshow.PackageError, "unsupported format"):
            zshow.validate_package(bytes(package))


if __name__ == "__main__":
    unittest.main()
