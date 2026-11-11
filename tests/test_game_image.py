import struct
import subprocess
import sys
import tempfile
import unittest
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from game_image import HEADER, pack, validate
from deploy_game import deploy


BOUNDS = {"ram_bytes": 8192, "stack_bytes": 1024, "abi": 1}


class GameImageTest(unittest.TestCase):
    def test_wire_format_and_crc_vectors(self):
        self.assertEqual(zlib.crc32(b""), 0)
        self.assertEqual(zlib.crc32(b"\x00"), 0xd202ef8d)
        self.assertEqual(zlib.crc32(b"123456789"), 0xcbf43926)
        payload = b"123456789"
        image = pack(payload, **BOUNDS)
        self.assertEqual(HEADER.size, 32)
        self.assertEqual(image[:8], b"LUNA\x01\x00\x01\x00")
        self.assertEqual(struct.unpack_from("<I", image, 24)[0], 0xcbf43926)
        self.assertEqual(validate(image, **BOUNDS)["size"], 9)

    def test_bounds_and_alignment(self):
        for size, load, entry, valid in (
            (0, 0, 0, False), (1, 0, 0, False), (4, 0, 0, True),
            (7168, 0, 7164, True), (7169, 0, 0, False),
            (4, 7164, 7164, True), (8, 7164, 7164, False),
            (8, 2, 4, False), (8, 0, 2, False),
            (8, 0, 8, False), (4, 0xfffffffc, 0xfffffffc, False),
        ):
            with self.subTest(size=size, load=load, entry=entry):
                if valid:
                    pack(bytes(size), load=load, entry=entry, **BOUNDS)
                else:
                    with self.assertRaises(ValueError):
                        pack(bytes(size), load=load, entry=entry, **BOUNDS)

    def test_reject_corruption_truncation_and_extensions(self):
        image = pack(bytes(range(16)), **BOUNDS)
        for offset in range(len(image)):
            damaged = bytearray(image)
            damaged[offset] ^= 1
            with self.subTest(offset=offset), self.assertRaises(ValueError):
                validate(damaged, **BOUNDS)
        for damaged in (image[:31], image[:-1], image + b"\x00"):
            with self.assertRaises(ValueError):
                validate(damaged, **BOUNDS)

    def test_semantics_with_valid_header_crc(self):
        image = pack(bytes(16), **BOUNDS)
        for offset, value, width in ((6, 2, 2), (20, 1, 4), (8, 0xffffffff, 4),
                                     (12, 0xfffffffc, 4), (16, 16, 4)):
            damaged = bytearray(image)
            damaged[offset:offset+width] = value.to_bytes(width, "little")
            struct.pack_into("<I", damaged, 28, zlib.crc32(damaged[:28]))
            with self.assertRaises(ValueError):
                validate(damaged, **BOUNDS)

    def test_packer_never_overwrites_raw_input(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "smoke.bin"
            source.write_bytes(bytes(4))
            script = Path(__file__).resolve().parents[1] / "scripts/game_image.py"
            result = subprocess.run([sys.executable, str(script), "pack", str(source),
                                     str(source)], capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(source.read_bytes(), bytes(4))

    def test_deploy_readback_backup_and_no_invalid_write(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            directory = root / "GAMES"
            directory.mkdir()
            source = root / "LUNAR.BIN"
            first = pack(bytes(4), **BOUNDS)
            second = pack(bytes(8), **BOUNDS)
            source.write_bytes(first)
            destination = deploy(source, directory)
            self.assertEqual(destination.read_bytes(), first)
            deploy(source, directory)
            self.assertFalse((directory / "BACKUP").exists())
            source.write_bytes(second)
            deploy(source, directory)
            self.assertEqual(destination.read_bytes(), second)
            self.assertEqual(next((directory / "BACKUP").iterdir()).read_bytes(), first)
            source.write_bytes(b"invalid")
            with self.assertRaises(ValueError):
                deploy(source, directory)
            self.assertEqual(destination.read_bytes(), second)
            self.assertFalse(list(directory.glob("*.TMP")))


if __name__ == "__main__":
    unittest.main()
