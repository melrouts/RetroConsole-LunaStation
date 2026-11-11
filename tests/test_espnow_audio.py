from array import array
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
RECEIVER = ROOT / "examples/espnow-counter/espnow-counter-rx"


class StartupChimeTest(unittest.TestCase):
    def test_pcm_envelope_stereo_and_replay(self):
        source = r'''
#include <algorithm>
#include <cassert>
#include <cstdio>
#include <vector>
#include "startup_chime.h"

int main() {
    StartupChime chime;
    int16_t idle[256];
    chime.render(idle, 128);
    assert(!chime.playing());
    for (int16_t sample : idle) assert(sample == 0);

    const size_t frames = StartupChime::TOTAL_FRAMES;
    std::vector<int16_t> first(frames * 2);
    chime.play();
    chime.render(first.data(), frames - 1);
    assert(chime.playing());
    chime.render(first.data() + (frames - 1) * 2, 1);
    assert(!chime.playing());

    std::fill_n(idle, 256, 123);
    chime.render(idle, 128);
    for (int16_t sample : idle) assert(sample == 0);

    std::vector<int16_t> replay(frames * 2);
    chime.play();
    for (size_t offset = 0; offset < frames; offset += 127) {
        chime.render(replay.data() + offset * 2,
                     std::min(size_t(127), frames - offset));
    }
    assert(!chime.playing());
    assert(first == replay);
    return std::fwrite(first.data(), sizeof(int16_t), first.size(), stdout)
                   == first.size() ? 0 : 1;
}
'''
        with tempfile.TemporaryDirectory() as directory:
            program = Path(directory) / "startup_chime_test"
            subprocess.run(
                ["c++", "-std=c++11", "-Wall", "-Wextra", "-Werror",
                 "-I", str(RECEIVER), "-x", "c++", "-", "-o", str(program)],
                input=source, text=True, check=True,
            )
            result = subprocess.run(
                [str(program)], capture_output=True, check=True,
            )

        samples = array("h")
        samples.frombytes(result.stdout)
        left, right = samples[::2], samples[1::2]
        self.assertEqual(len(left), 9600)  # 0.6 s at 16 kHz.
        self.assertEqual(left, right)
        self.assertLessEqual(max(abs(value) for value in left), 7500)
        self.assertGreater(max(left), 7490)
        self.assertLess(min(left), -7490)

        for index, frequency in enumerate((523.25, 659.25, 783.99)):
            note = left[index * 3200:index * 3200 + 2560]
            pause = left[index * 3200 + 2560:(index + 1) * 3200]
            self.assertEqual(note[0], 0)
            self.assertEqual(note[-1], 0)
            self.assertTrue(all(value == 0 for value in pause))
            for frame in range(128):
                limit = 7500 * frame / 128 + 1
                self.assertLessEqual(abs(note[frame]), limit)
                self.assertLessEqual(abs(note[-1 - frame]), limit)
            crossings = [
                i for i in range(1, len(note))
                if note[i - 1] <= 0 < note[i]
            ]
            measured = (len(crossings) - 1) * 16000 / (crossings[-1] - crossings[0])
            self.assertAlmostEqual(measured, frequency, delta=1)


if __name__ == "__main__":
    unittest.main()
