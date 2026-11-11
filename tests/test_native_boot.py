import ctypes
import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from game_image import pack


ROOT = Path(__file__).resolve().parents[1]
READER = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32,
                         ctypes.POINTER(ctypes.c_uint8))
WRITER = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32,
                         ctypes.POINTER(ctypes.c_uint8))


class Volume(ctypes.Structure):
    _fields_ = [("read", READER), ("context", ctypes.c_void_p)] + [
        (name, ctypes.c_uint32) for name in
        ("start", "total", "fat", "fat_start", "fat_sectors", "data", "clusters",
         "root", "root_sectors", "root_cluster")
    ] + [("sectors_per_cluster", ctypes.c_uint8), ("fat32", ctypes.c_uint8),
        ("fat_count", ctypes.c_uint8), ("fat_active", ctypes.c_uint8),
        ("fat_mirror", ctypes.c_uint8),
        ("sector", ctypes.c_uint8 * 512)]


class File(ctypes.Structure):
    _fields_ = [("volume", ctypes.POINTER(Volume)), ("cluster", ctypes.c_uint32),
                ("size", ctypes.c_uint32), ("name", ctypes.c_char * 13)]


class Image(ctypes.Structure):
    _fields_ = [(name, ctypes.c_uint32) for name in ("size", "load", "entry", "payload_crc")]


def directory_entry(name, attributes, cluster, size=0):
    entry = bytearray(32)
    entry[:11] = name
    entry[11] = attributes
    struct.pack_into("<H", entry, 20, cluster >> 16)
    struct.pack_into("<H", entry, 26, cluster & 0xffff)
    struct.pack_into("<I", entry, 28, size)
    return entry


def disk_fixture(fat32=False, image=None, fragmented=True):
    if image is None:
        image = pack(bytes(i % 251 for i in range(1100)), ram_bytes=8192,
                     stack_bytes=1024, abi=1)
    reserved = 32 if fat32 else 1
    fats = 512 if fat32 else 20
    roots = 0 if fat32 else 2
    clusters = 65525 if fat32 else 5000
    data = reserved + fats + roots
    total = data + clusters
    start = 32
    sectors = {}
    mbr = bytearray(512)
    mbr[450] = 0x0c if fat32 else 0x06
    struct.pack_into("<II", mbr, 454, start, total)
    mbr[510:] = b"\x55\xaa"
    sectors[0] = mbr
    bpb = bytearray(512)
    bpb[:3] = b"\xeb\x3c\x90"
    struct.pack_into("<H", bpb, 11, 512)
    bpb[13] = 1
    struct.pack_into("<H", bpb, 14, reserved)
    bpb[16] = 1
    struct.pack_into("<H", bpb, 17, 0 if fat32 else 32)
    struct.pack_into("<I", bpb, 32, total)
    struct.pack_into("<I" if fat32 else "<H", bpb, 36 if fat32 else 22, fats)
    if fat32:
        struct.pack_into("<I", bpb, 44, 2)
    bpb[510:] = b"\x55\xaa"
    sectors[start] = bpb
    fat = bytearray(512)

    def link(cluster, value):
        struct.pack_into("<I" if fat32 else "<H", fat, cluster * (4 if fat32 else 2), value)

    end = 0x0fffffff if fat32 else 0xffff
    link(2, end)
    link(5, 7 if fragmented else end)
    link(7, end)
    needed = (len(image) + 511) // 512
    chain = [8, 11, 9] + list(range(12, 12 + needed)) if fragmented else list(range(8, 8 + needed))
    for index, cluster in enumerate(chain[:needed]):
        link(cluster, chain[index + 1] if index + 1 < needed else end)
        sectors[start + data + cluster - 2] = image[index*512:(index+1)*512].ljust(512, b"\0")
    sectors[start + reserved] = fat
    root = bytearray(512)
    root[:32] = directory_entry(b"GAMES      ", 0x10, 5)
    sectors[start + data if fat32 else start + reserved + fats] = root
    games = bytearray(512)
    games[:32] = directory_entry(b"BACKUP     ", 0x10, 6)
    games[32:64] = directory_entry(b"BAD     BIN", 0x02, 6, 99)
    games[64:96] = directory_entry(b"SMOKE   bin", 0x20, 8, len(image))
    games[96:128] = directory_entry(b"OTHER   BIN", 0x20, 8, len(image))
    games[128:160] = directory_entry(b"README  TXT", 0x20, 8, 24)
    if fragmented:
        deleted = bytearray(512)
        for i in range(0, 512, 32):
            deleted[i] = 0xe5
        sectors[start + data + 3] = deleted  # GAMES cluster 5
        sectors[start + data + 5] = games    # GAMES continuation cluster 7
    else:
        sectors[start + data + 3] = games
    return sectors, image


class NativeBootTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory()
        library = Path(cls.temporary.name) / "boot.dylib"
        subprocess.run(["cc", "-std=c11", "-Wall", "-Wextra", "-Werror", "-O2",
                        "-shared", "-fPIC", str(ROOT / "firmware/fat.c"),
                        str(ROOT / "firmware/image.c"), "-o", str(library)], check=True)
        cls.lib = ctypes.CDLL(str(library))
        cls.lib.fat_mount.argtypes = [ctypes.POINTER(Volume), READER, ctypes.c_void_p]
        cls.lib.fat_first_game.argtypes = [ctypes.POINTER(Volume), ctypes.POINTER(File)]
        cls.lib.fat_game_named.argtypes = [ctypes.POINTER(Volume), ctypes.POINTER(File), ctypes.c_char_p]
        cls.lib.fat_game_count.argtypes = [ctypes.POINTER(Volume), ctypes.POINTER(ctypes.c_uint32)]
        cls.lib.fat_game_at.argtypes = [ctypes.POINTER(Volume), ctypes.c_uint32,
                                      ctypes.POINTER(File)]
        cls.lib.fat_settings_read.argtypes = [ctypes.POINTER(Volume),
                                              ctypes.POINTER(ctypes.c_uint8),
                                              ctypes.POINTER(ctypes.c_uint8)]
        cls.lib.fat_settings_write.argtypes = [ctypes.POINTER(Volume), WRITER,
                                               ctypes.c_uint8, ctypes.c_uint8]
        cls.lib.fat_read_file.argtypes = [ctypes.POINTER(File), ctypes.c_uint32,
                                        ctypes.POINTER(ctypes.c_uint8), ctypes.c_uint32]
        cls.lib.image_header.argtypes = [ctypes.POINTER(ctypes.c_uint8), ctypes.c_uint32,
                                        ctypes.c_uint32, ctypes.c_uint32, ctypes.c_uint16,
                                        ctypes.POINTER(Image)]
        cls.lib.image_crc.argtypes = [ctypes.c_uint32, ctypes.POINTER(ctypes.c_uint8),
                                     ctypes.c_uint32]
        cls.lib.image_crc.restype = ctypes.c_uint32

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def mount(self, sectors):
        def read(_context, lba, target):
            data = sectors.get(lba)
            if data is None:
                return -1
            ctypes.memmove(target, bytes(data), 512)
            return 0
        callback = READER(read)
        volume = Volume()
        status = self.lib.fat_mount(ctypes.byref(volume), callback, None)
        return status, volume, callback

    def test_fragmented_fat16_and_fat32_subdirectory_files(self):
        for fat32 in (False, True):
            with self.subTest(fat32=fat32):
                sectors, image = disk_fixture(fat32)
                status, volume, callback = self.mount(sectors)
                self.assertEqual(status, 0)
                self.assertEqual(bool(volume.fat32), fat32)
                file = File()
                self.assertEqual(self.lib.fat_first_game(ctypes.byref(volume), ctypes.byref(file)), 0)
                self.assertEqual(file.name, b"SMOKE.bin")
                count = ctypes.c_uint32()
                self.assertEqual(self.lib.fat_game_count(ctypes.byref(volume),
                                                        ctypes.byref(count)), 0)
                self.assertEqual(count.value, 2)
                second = File()
                self.assertEqual(self.lib.fat_game_at(ctypes.byref(volume), 1,
                                                     ctypes.byref(second)), 0)
                self.assertEqual(second.name, b"OTHER.BIN")
                self.assertEqual(self.lib.fat_game_at(ctypes.byref(volume), 2,
                                                     ctypes.byref(second)), 3)
                output = (ctypes.c_uint8 * len(image))()
                self.assertEqual(self.lib.fat_read_file(ctypes.byref(file), 0, output, len(image)), 0)
                self.assertEqual(bytes(output), image)
                partial = (ctypes.c_uint8 * 33)()
                self.assertEqual(self.lib.fat_read_file(ctypes.byref(file), 501, partial, 33), 0)
                self.assertEqual(bytes(partial), image[501:534])
                self.assertEqual(self.lib.fat_read_file(ctypes.byref(file), len(image), partial, 1), 5)
                self.assertEqual(self.lib.image_header(output, len(image), 8192, 1024, 1,
                                                      ctypes.byref(Image())), 0)
                self.assertIsNotNone(callback)

    def test_bad_geometry_short_chain_and_bounded_directory_cycle(self):
        for offset, value in ((11, 1), (13, 3), (16, 0), (14, 0)):
            sectors, _ = disk_fixture()
            sectors[32][offset] = value
            status, _, _ = self.mount(sectors)
            self.assertEqual(status, 2)
        sectors, image = disk_fixture()
        status, volume, callback = self.mount(sectors)
        self.assertEqual(status, 0)
        struct.pack_into("<H", sectors[33], 5*2, 5)
        self.assertEqual(self.lib.fat_first_game(ctypes.byref(volume), ctypes.byref(File())), 5)
        struct.pack_into("<H", sectors[33], 5*2, 7)
        file = File()
        self.assertEqual(self.lib.fat_first_game(ctypes.byref(volume), ctypes.byref(file)), 0)
        struct.pack_into("<H", sectors[33], 8*2, 0xffff)
        output = (ctypes.c_uint8 * len(image))()
        self.assertEqual(self.lib.fat_read_file(ctypes.byref(file), 0, output, len(image)), 4)
        self.assertIsNotNone(callback)

    def test_named_game_lookup_does_not_choose_first_bin(self):
        for fat32 in (False, True):
            sectors, image = disk_fixture(fat32)
            status, volume, callback = self.mount(sectors)
            self.assertEqual(status, 0)
            file = File()
            self.assertEqual(self.lib.fat_game_named(ctypes.byref(volume), ctypes.byref(file),
                                                    b"LUNAR   BIN"), 3)
            games = sectors[volume.start + volume.data + 5]
            games[96:128] = directory_entry(b"LUNAR   BIN", 0x20, 8, len(image))
            self.assertEqual(self.lib.fat_game_named(ctypes.byref(volume), ctypes.byref(file),
                                                    b"LUNAR   BIN"), 0)
            self.assertEqual(file.name, b"LUNAR.BIN")
            self.assertIsNotNone(callback)

    def test_settings_file_creation_and_update_on_fat16_and_fat32(self):
        for fat32 in (False, True):
            with self.subTest(fat32=fat32):
                sectors, _ = disk_fixture(fat32)
                status, volume, _ = self.mount(sectors)
                self.assertEqual(status, 0)
                music, effects = ctypes.c_uint8(0), ctypes.c_uint8(0)
                self.assertEqual(self.lib.fat_settings_read(ctypes.byref(volume),
                                                            ctypes.byref(music),
                                                            ctypes.byref(effects)), 3)

                def write(_context, lba, source):
                    sectors[lba] = bytearray(ctypes.string_at(source, 512))
                    return 0

                writer = WRITER(write)
                self.assertEqual(self.lib.fat_settings_write(ctypes.byref(volume), writer, 3, 5), 0)
                self.assertEqual(self.lib.fat_settings_read(ctypes.byref(volume),
                                                            ctypes.byref(music),
                                                            ctypes.byref(effects)), 0)
                self.assertEqual((music.value, effects.value), (3, 5))
                self.assertEqual(self.lib.fat_settings_write(ctypes.byref(volume), writer, 0, 7), 0)
                self.assertEqual(self.lib.fat_settings_read(ctypes.byref(volume),
                                                            ctypes.byref(music),
                                                            ctypes.byref(effects)), 0)
                self.assertEqual((music.value, effects.value), (0, 7))

    def test_native_header_matches_host_packer_and_crc(self):
        import zlib
        image = pack(b"123456789", ram_bytes=8192, stack_bytes=1024, abi=1)
        payload = (ctypes.c_uint8 * 9).from_buffer_copy(image[32:])
        self.assertEqual(self.lib.image_crc(0xffffffff, payload, 9) ^ 0xffffffff, 0xcbf43926)
        header = (ctypes.c_uint8 * 32).from_buffer_copy(image[:32])
        parsed = Image()
        self.assertEqual(self.lib.image_header(header, len(image), 8192, 1024, 1,
                                              ctypes.byref(parsed)), 0)
        self.assertEqual((parsed.size, parsed.load, parsed.entry), (9, 0, 0))
        for offset in range(32):
            bad = bytearray(image[:32])
            bad[offset] ^= 1
            header = (ctypes.c_uint8 * 32).from_buffer_copy(bad)
            self.assertNotEqual(self.lib.image_header(header, len(image), 8192, 1024, 1,
                                                     ctypes.byref(parsed)), 0)
        bad = bytearray(image[:32])
        struct.pack_into("<I", bad, 12, 0xfffffffc)
        struct.pack_into("<I", bad, 28, zlib.crc32(bad[:28]))
        header = (ctypes.c_uint8 * 32).from_buffer_copy(bad)
        self.assertEqual(self.lib.image_header(header, len(image), 8192, 1024, 1,
                                              ctypes.byref(parsed)), 4)


if __name__ == "__main__":
    unittest.main()
