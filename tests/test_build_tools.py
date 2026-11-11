import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class BuildToolsTest(unittest.TestCase):
    def test_hex_padding_and_capacity(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "image.bin"
            output = Path(directory) / "image.hex"
            source.write_bytes(b"\x01\x23\x45\x67\x89")
            command = [sys.executable, str(ROOT / "scripts/bin_to_hex.py"),
                       str(source), str(output), "--ram-bytes", "8"]
            subprocess.run(command, check=True, capture_output=True)
            self.assertEqual(output.read_text(), "67452301\n00000089\n")
            output.unlink()
            source.write_bytes(bytes(9))
            result = subprocess.run(command, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(output.exists())

    def test_timing_gate(self):
        with tempfile.TemporaryDirectory() as directory:
            report = Path(directory) / "timing.json"
            command = [sys.executable, str(ROOT / "scripts/check_timing.py"), str(report)]
            for achieved, constraint, used, expected in [
                (27, 27, 4, True),
                (26.99, 27, 4, False),
                (62, 0, 4, False),
                (62, 27, 27, False),
            ]:
                report.write_text(json.dumps({
                    "fmax": {"clk": {"achieved": achieved, "constraint": constraint}},
                    "utilization": {"BSRAM": {"used": used, "available": 26}},
                }))
                with self.subTest(achieved=achieved, constraint=constraint, used=used):
                    result = subprocess.run(command, capture_output=True)
                    self.assertEqual(result.returncode == 0, expected)
            report.write_text('{"fmax": {}, "utilization": {}}')
            self.assertNotEqual(subprocess.run(command, capture_output=True).returncode, 0)

    def test_video_clocks_and_serializer_placeholders(self):
        with tempfile.TemporaryDirectory() as directory:
            report = Path(directory) / "timing.json"
            command = [sys.executable, str(ROOT / "scripts/check_timing.py"), str(report),
                       "--min-mhz", "25.2", "--expect-mhz", "25.2", "--expect-mhz", "27"]
            data = {
                "fmax": {"sys": {"achieved": 50, "constraint": 27},
                         "pixel": {"achieved": 45, "constraint": 25.2}},
                "utilization": {"IOLOGIC_DUMMY": {"used": 3, "available": 0},
                                "BSRAM": {"used": 4, "available": 26}},
            }
            report.write_text(json.dumps(data))
            self.assertEqual(subprocess.run(command, capture_output=True).returncode, 0)
            data["fmax"]["pixel"]["constraint"] = 27
            report.write_text(json.dumps(data))
            self.assertNotEqual(subprocess.run(command, capture_output=True).returncode, 0)
            del data["fmax"]["pixel"]
            report.write_text(json.dumps(data))
            self.assertNotEqual(subprocess.run(command, capture_output=True).returncode, 0)


if __name__ == "__main__":
    unittest.main()
