import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("memorial_assets", ROOT / "scripts/memorial_assets.py")
assets = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(assets)


class MemorialAssetsTest(unittest.TestCase):
    def test_photographs_fit_two_block_roms_and_keep_all_four_tones(self):
        for source in assets.SOURCES:
            with self.subTest(source=source):
                pixels = assets.photograph(ROOT / "photos" / source)
                self.assertEqual(len(pixels), 8192)
                self.assertEqual(set(pixels), {0, 1, 2, 3})
                self.assertEqual(pixels, assets.photograph(ROOT / "photos" / source))

    def test_caption_rom_exact_width_and_required_english_quotes(self):
        self.assertEqual(len(assets.TEXT), 16)
        self.assertEqual(len(assets.SCREEN_TEXT), 16)
        self.assertTrue(all(len(line) <= 32 and line.isascii()
                            for line in assets.TEXT + assets.SCREEN_TEXT))
        self.assertEqual(assets.TEXT[4], "FIRST FAX FROM THE MOON :)")
        self.assertEqual(assets.TEXT[8], "THE EAGLE HAS LANDED")
        self.assertEqual(assets.TEXT[10:12],
                         ("ONE SMALL STEP FOR A MAN,", "ONE GIANT LEAP FOR MANKIND."))
        self.assertEqual(assets.SCREEN_TEXT[7], "Eduard Garanskij  retro@lea.lt")

    def test_caption_rom_layout_matches_renderer_addresses(self):
        rom = assets.caption_rom()
        self.assertEqual(len(rom), 2048)
        self.assertTrue(rom.isascii())

        def line(number):
            return rom[number * 32:(number + 1) * 32]

        # Lines 0-15 are the memorial captions, 16-31 the menu and messages that
        # the renderer addresses as {line, column}; they must not move.
        self.assertEqual(line(0).strip(), "LUNA 9 - 1966")
        self.assertEqual(line(16).strip(), "LUNAR")
        self.assertEqual(line(23), "Eduard Garanskij  retro@lea.lt  ")
        self.assertEqual(line(28).strip(), "LANDED! NEXT RELEASE WINDOW")
        self.assertEqual(line(29).strip(), "CRASHED - CAPSULE LOST")
        self.assertEqual(line(30).strip(), "GAME OVER - W TO RESTART")
        # Lines 32-35 follow the failure bits of the landing result in order.
        self.assertEqual([line(number).strip() for number in range(32, 36)],
                         ["MISSED THE LANDING PAD", "DESCENT SPEED TOO HIGH",
                          "SIDE SPEED TOO HIGH", "TILT ANGLE TOO LARGE"])
        self.assertEqual(line(36), "POINTS".ljust(32))
        self.assertEqual([line(number).strip() for number in range(37, 49)],
                         list(assets.CONSOLE_TEXT))
        self.assertEqual(rom[49 * 32:], " " * (2048 - 49 * 32))
        self.assertTrue(all(len(text) <= 32 for text in assets.CAUSE_TEXT))
        self.assertTrue(all(len(text) <= 32 for text in assets.CONSOLE_TEXT))

    def test_written_caption_hex_has_one_entry_per_rom_address(self):
        with tempfile.TemporaryDirectory() as directory:
            assets.main(Path(directory))
            hex_lines = (Path(directory) / "memorial-text.hex").read_text().split()
        self.assertEqual(len(hex_lines), 2048)
        self.assertEqual("".join(chr(int(value, 16)) for value in hex_lines),
                         assets.caption_rom())


if __name__ == "__main__":
    unittest.main()
