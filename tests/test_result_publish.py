"""Run the real game loop and check the landing result it hands to the video block."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PLAY, LANDED, CRASHED, GAME_OVER = 0, 3, 4, 5
FAIL_PAD, FAIL_VERTICAL, FAIL_HORIZONTAL, FAIL_TILT = 1, 2, 4, 8
OFF_PAD = 3
# level, capsules, pad, vx, vy, angle, fuel, expected state, expected cause bits
SCENARIOS = (
    (1, 3, 0, 0, 10*256, 0, 900*256, LANDED, 0),
    (1, 3, 1, -300, 20*256, 400, 640*256, LANDED, 0),
    (7, 3, 2, 700, 20*256, -500, 100*256, LANDED, 0),
    (50, 3, 0, 0, 10*256, 0, 620*256, LANDED, 0),
    (99, 3, 2, 0, 10*256, 0, 620*256, LANDED, 0),
    (1, 3, OFF_PAD, 0, 10*256, 0, 900*256, CRASHED, FAIL_PAD),
    (3, 2, 1, 0, 60*256, 0, 900*256, CRASHED, FAIL_VERTICAL),
    (1, 3, 0, 80*256, 10*256, 8000, 900*256, CRASHED, FAIL_HORIZONTAL | FAIL_TILT),
    (1, 1, OFF_PAD, 80*256, 60*256, 8000, 0, GAME_OVER,
     FAIL_PAD | FAIL_VERTICAL | FAIL_HORIZONTAL | FAIL_TILT),
)
HARNESS = r'''
#include <assert.h>
#include <setjmp.h>
#include <stdint.h>
#include "mmio.h"
static uint32_t registers[64], terrain[640];
static volatile uint32_t *sim_mmio(unsigned offset);
#undef MMIO32
#define MMIO32(offset) (*sim_mmio(offset))
#undef TERRAIN_COLUMN
#define TERRAIN_COLUMN(index) terrain[index]
#define main firmware_main
#include "game.c"
#undef main

#define OFF_PAD 3
static const struct scenario {
    unsigned level, capsules, pad;
    int32_t vx, vy, angle, fuel;
    unsigned state, cause;
} scenarios[] = { SCENARIO_TABLE };
static jmp_buf finished;
static unsigned scenario, iteration;

/* The published words must keep the pad edges and carry the result above them. */
static void check_words(int expect_result)
{
    uint32_t packed = 0, points = 0;
    for (unsigned pad = 0; pad < 3; ++pad) {
        uint32_t word = registers[0x50/4 + pad];
        assert((word & 0x3ff) == game.pad_start[pad] * 640u / 24u);
        assert(((word >> 16) & 0x3ff) == game.pad_end[pad] * 640u / 24u);
        packed |= (((word >> 10) & 63u) | (((word >> 26) & 63u) << 6)) << (pad * 12);
    }
    assert(packed >> 24 == 0);
    for (unsigned digit = 5; digit--;) {
        unsigned nibble = (packed >> (digit * 4)) & 15u;
        assert(nibble <= 9);
        points = points * 10 + nibble;
    }
    if (expect_result)
        assert(points == game.gained && (packed >> 20) == game.cause);
    else
        assert(packed == 0);
}

static void observe(void)
{
    const struct scenario *s = &scenarios[scenario];
    unsigned events = 0;
    registers[0] = 0;
    if (iteration == 0) {
        assert(state == MAIN_SCREEN);
        check_words(0);
        events = 2;
    } else if (iteration == 1) {
        assert(state == PLAY);
        check_words(0);
        game.level = s->level;
        game_level(&game);
        game.capsules = s->capsules;
        game.ship.fuel = s->fuel;
        /* Segment 0 is never part of a pad, so it is a safe place to miss them all. */
        game.ship.x = s->pad == OFF_PAD ? 800 * 256 / 48
                      : (int32_t)(game.pad_start[s->pad] + game.pad_end[s->pad]) * (800 * 256) / 48;
        game.ship.y = game_ground(&game, game.ship.x) - 11 * 256;
        game.ship.vx = s->vx;
        game.ship.vy = s->vy;
        game.ship.angle = s->angle;
    } else {
        unsigned frame = iteration - 2;
        unsigned shown = s->state == GAME_OVER ? 900 : 180;
        if (frame < shown) {
            assert(state == s->state && age == frame);
            assert(((registers[0x44/4] >> 4) & 15) == state);
            check_words(1);
            assert(game.cause == s->cause);
            assert((game.gained == 0) == (s->cause != 0));
            assert((game.outcome == 1) == (s->state == LANDED));
        } else {
            unsigned next = s->level + (s->state == LANDED && s->level < 99);
            assert(age == 0);
            check_words(0);
            if (s->state == GAME_OVER) {
                assert(state == MAIN_SCREEN);
            } else {
                assert(state == PLAY && game.level == next);
                assert(game.gained == 0 && game.cause == 0);
            }
            longjmp(finished, 1);
        }
    }
    assert(iteration < 5000);
    registers[1] = events;
    ++iteration;
}

static volatile uint32_t *sim_mmio(unsigned offset)
{
    if (offset == 0x14)
        ++registers[offset/4];
    else if (offset == 4 && registers[0x30/4] == 7 && registers[1] == 0xff)
        observe();
    return &registers[offset/4];
}

int main(void)
{
    registers[0x1c/4] = registers[0x20/4] = 1;
    for (scenario = 0; scenario < sizeof scenarios / sizeof *scenarios; ++scenario) {
        iteration = 0;
        best = 0;
        registers[0x30/4] = 0;
        registers[0x70/4] = AUDIO_LINK_VERSION;
        if (!setjmp(finished))
            firmware_main();
    }
    return 0;
}
'''


def table():
    names = {OFF_PAD: "OFF_PAD"}
    rows = []
    for level, capsules, pad, vx, vy, angle, fuel, state, cause in SCENARIOS:
        rows.append("{%d, %d, %s, %d, %d, %d, %d, %d, %d}" %
                    (level, capsules, names.get(pad, pad), vx, vy, angle, fuel, state, cause))
    return ",\n    ".join(rows)


class ResultPublishTest(unittest.TestCase):
    def test_points_and_failure_causes_reach_the_video_block_only_on_result_screens(self):
        with tempfile.TemporaryDirectory() as directory:
            source, executable = Path(directory)/"result.c", Path(directory)/"result"
            source.write_text(HARNESS.replace("SCENARIO_TABLE", table()))
            subprocess.run(["cc", "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror",
                            "-I"+str(ROOT/"firmware"), "-I"+str(ROOT/"build"),
                            str(source), str(ROOT/"firmware/game_engine.c"),
                            "-o", str(executable)], check=True)
            subprocess.run([str(executable)], check=True, timeout=30)


if __name__ == "__main__":
    unittest.main()
