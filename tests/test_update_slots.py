import ctypes
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest

from test_native_boot import ROOT, READER, Volume, directory_entry, disk_fixture
from game_image import pack


WRITER = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32,
                         ctypes.POINTER(ctypes.c_uint8))


class Slot(ctypes.Structure):
    _fields_ = [("sectors", ctypes.c_uint32 * 16),
                ("generation", ctypes.c_uint32), ("size", ctypes.c_uint32)]


def update_fixture():
    sectors, original = disk_fixture(fragmented=False)
    for index, first in enumerate((32, 64)):
        for offset in range(16):
            cluster = first + offset
            struct.pack_into("<H", sectors[33], cluster*2,
                             cluster+1 if offset < 15 else 0xffff)
            sectors[55 + cluster - 2] = bytearray(512)
        name = b"UPDATEA BIN" if index == 0 else b"UPDATEB BIN"
        sectors[58][96+index*32:128+index*32] = directory_entry(name, 0x20, first, 8192)
    return sectors, original


class UpdateSlotsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        path = Path(cls.temp.name) / "updates.dylib"
        subprocess.run(["cc", "-std=c11", "-Wall", "-Wextra", "-Werror", "-O2",
                        "-shared", "-fPIC", *(str(ROOT / "firmware" / filename) for filename in
                                              ("fat.c", "image.c", "update.c")), "-o", str(path)], check=True)
        cls.lib = ctypes.CDLL(str(path))
        cls.lib.fat_mount.argtypes = [ctypes.POINTER(Volume), READER, ctypes.c_void_p]
        cls.lib.update_prepare.argtypes = [ctypes.POINTER(Volume), ctypes.POINTER(Slot)]
        cls.lib.update_validate.argtypes = [ctypes.POINTER(Volume), ctypes.POINTER(Slot)]
        cls.lib.update_commit.argtypes = [ctypes.POINTER(Volume), WRITER, ctypes.POINTER(Slot),
                                         ctypes.POINTER(ctypes.c_uint8), ctypes.c_uint32, ctypes.c_uint32]

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def mount(self, sectors, fail_write=0, corrupt_write=0):
        writes = []
        def read(_, lba, target):
            if lba not in sectors:
                return -1
            ctypes.memmove(target, bytes(sectors[lba]), 512)
            return 0
        def write(_, lba, source):
            writes.append(lba)
            if len(writes) == fail_write:
                return -1
            sectors[lba] = bytearray(ctypes.string_at(source, 512))
            if len(writes) == corrupt_write:
                sectors[lba][10] ^= 1
            return 0
        reader, writer = READER(read), WRITER(write)
        volume = Volume()
        self.assertEqual(self.lib.fat_mount(ctypes.byref(volume), reader, None), 0)
        slots = (Slot*2)()
        return volume, slots, reader, writer, writes

    def image(self):
        data = pack(bytes(i % 251 for i in range(1800)), ram_bytes=8192, stack_bytes=1024, abi=1)
        return (ctypes.c_uint8 * len(data)).from_buffer_copy(data)

    def test_commit_and_readback_only_touch_inactive_slot(self):
        sectors, _ = update_fixture()
        before = {lba: bytes(data) for lba, data in sectors.items()}
        v, slots, reader, writer, writes = self.mount(sectors)
        self.assertEqual(self.lib.update_prepare(ctypes.byref(v), slots), 0)
        image = self.image()
        self.assertEqual(self.lib.update_commit(ctypes.byref(v), writer, ctypes.byref(slots[0]),
                                               image, len(image), 1), 0)
        self.assertEqual(self.lib.update_validate(ctypes.byref(v), ctypes.byref(slots[0])), 0)
        self.assertEqual(slots[0].generation, 1)
        allowed = set(slots[0].sectors)
        self.assertTrue(set(writes) <= allowed)
        for lba in before:
            if lba not in allowed:
                self.assertEqual(bytes(sectors[lba]), before[lba])
        self.assertIsNotNone(reader)

    def test_every_interrupted_or_corrupted_write_preserves_previous_slot(self):
        for fault in ("fail", "corrupt"):
            for operation in range(1, 7):
                sectors, _ = update_fixture()
                v, slots, reader, writer, _ = self.mount(sectors)
                self.assertEqual(self.lib.update_prepare(ctypes.byref(v), slots), 0)
                image = self.image()
                self.assertEqual(self.lib.update_commit(ctypes.byref(v), writer, ctypes.byref(slots[0]),
                                                       image, len(image), 1), 0)
                old = [bytes(sectors[lba]) for lba in slots[0].sectors]
                v, slots, reader, writer, _ = self.mount(sectors,
                    fail_write=operation if fault == "fail" else 0,
                    corrupt_write=operation if fault == "corrupt" else 0)
                self.assertEqual(self.lib.update_prepare(ctypes.byref(v), slots), 0)
                result = self.lib.update_commit(ctypes.byref(v), writer, ctypes.byref(slots[1]),
                                                image, len(image), 2)
                # Corrupting the all-zero invalidation sector is safe: its CRC is invalid,
                # and the subsequent complete data+commit supersedes it.
                if fault == "corrupt" and operation == 1:
                    self.assertEqual(result, 0)
                else:
                    self.assertNotEqual(result, 0, (fault, operation))
                    self.assertNotEqual(self.lib.update_validate(ctypes.byref(v), ctypes.byref(slots[1])), 0)
                self.assertEqual(self.lib.update_validate(ctypes.byref(v), ctypes.byref(slots[0])), 0)
                self.assertEqual([bytes(sectors[lba]) for lba in slots[0].sectors], old)
                self.assertIsNotNone(reader)

    def test_bad_image_or_aliased_slot_is_rejected_before_writes(self):
        sectors, _ = update_fixture()
        v, slots, reader, writer, writes = self.mount(sectors)
        self.assertEqual(self.lib.update_prepare(ctypes.byref(v), slots), 0)
        image = self.image()
        image[42] ^= 1
        self.assertNotEqual(self.lib.update_commit(ctypes.byref(v), writer, ctypes.byref(slots[0]),
                                                  image, len(image), 1), 0)
        self.assertEqual(writes, [])
        for cluster in (32, 8):
            struct.pack_into("<H", sectors[58], 128+26, cluster)
            self.assertNotEqual(self.lib.update_prepare(ctypes.byref(v), slots), 0)
        self.assertIsNotNone(reader)

    def test_slot_cannot_alias_games_directory(self):
        sectors, _ = update_fixture()
        # Cross-link the directory's first cluster into an otherwise long valid chain.
        struct.pack_into("<H", sectors[33], 5*2, 32)
        struct.pack_into("<H", sectors[58], 96+26, 5)
        v, slots, reader, _, _ = self.mount(sectors)
        self.assertNotEqual(self.lib.update_prepare(ctypes.byref(v), slots), 0)
        self.assertIsNotNone(reader)


if __name__ == "__main__":
    unittest.main()
