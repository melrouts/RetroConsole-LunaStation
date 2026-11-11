from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
RECEIVER = ROOT / "examples/espnow-counter/espnow-counter-rx"


class ButtonMappingTest(unittest.TestCase):
    def test_all_held_masks(self):
        source = r'''
#include <cstdio>
#include "button_mapping.h"

int main() {
    for (unsigned int mask = 0; mask < 16; ++mask) {
        std::printf("%u\n", remapControllerButtons(static_cast<uint8_t>(mask)));
    }
}
'''
        with tempfile.TemporaryDirectory() as directory:
            program = Path(directory) / "button_mapping_test"
            subprocess.run(
                ["c++", "-std=c++11", "-Wall", "-Wextra", "-Werror",
                 "-I", str(RECEIVER), "-x", "c++", "-", "-o", str(program)],
                input=source, text=True, check=True,
            )
            result = subprocess.run(
                [str(program)], capture_output=True, text=True, check=True,
            )

        self.assertEqual(
            [int(value) for value in result.stdout.splitlines()],
            [0x0, 0x1, 0x4, 0x5, 0x2, 0x3, 0x6, 0x7,
             0x8, 0x9, 0xc, 0xd, 0xa, 0xb, 0xe, 0xf],
        )


if __name__ == "__main__":
    unittest.main()
