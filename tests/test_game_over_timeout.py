"""Execute the real game loop and check the GAME_OVER inactivity timeout."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
HARNESS = r'''
#include <assert.h>
#include <setjmp.h>
#include <stdint.h>
#include <string.h>
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

enum { A = 1, W = 2, D = 4, B = 8, RELEASE_A = 0x10 };
/* "frame" counts loop iterations after the one that entered GAME_OVER. */
struct press { unsigned frame, events; };
static const struct scenario {
    unsigned held, leave, next;
    struct press presses[4];
} scenarios[] = {
    /* 15 s idle: still GAME_OVER on frame 899, menu on frame 900. */
    { .leave = 900, .next = MAIN_SCREEN },
    /* A or D (no other action in GAME_OVER) restarts the 15 s countdown. */
    { .presses = {{500, A}}, .leave = 1400, .next = MAIN_SCREEN },
    { .presses = {{899, D}}, .leave = 1799, .next = MAIN_SCREEN },
    { .presses = {{800, A}, {1600, D}, {2400, A}}, .leave = 3300, .next = MAIN_SCREEN },
    /* A held since the crash and a release edge are not new activity. */
    { .held = A, .presses = {{500, RELEASE_A}}, .leave = 900, .next = MAIN_SCREEN },
    /* W restarts and B opens the menu immediately, as before. */
    { .presses = {{300, W}}, .leave = 300, .next = PLAY },
    { .presses = {{899, W}}, .leave = 899, .next = PLAY },
    { .presses = {{300, B}}, .leave = 300, .next = MAIN_SCREEN },
};
static jmp_buf finished;
static unsigned scenario, iteration, last_reset;

static void observe(void)
{
    const struct scenario *s = &scenarios[scenario];
    unsigned events = 0;
    registers[0] = s->held;
    if (iteration == 0) {
        assert(state == MAIN_SCREEN);
        events = W;
    } else if (iteration == 1) {
        assert(state == PLAY);
        game.capsules = 1;
        game.score = 123;
        game.ship.vy = 99 * 256;
        game.ship.y = game_ground(&game, game.ship.x) - 11 * 256;
    } else {
        unsigned frame = iteration - 2;
        assert(((registers[0x44/4] >> 4) & 15) == state);
        if (frame < s->leave) {
            assert(state == GAME_OVER);
            assert(game.capsules == 0 && best == 123);
            assert(age == frame - last_reset);
        } else {
            struct game fresh;
            assert(state == s->next && age == 0 && best == 123);
            game_new(&fresh, 42);
            if (s->next == MAIN_SCREEN) {
                assert(!memcmp(&game, &fresh, sizeof game));
                assert(registers[0x4c/4] == 0x123);
            } else {
                assert(game.score == 0 && game.capsules == fresh.capsules);
            }
            longjmp(finished, 1);
        }
        for (const struct press *p = s->presses; p->frame; ++p) {
            if (p->frame == frame + 1) {
                events |= p->events;
                if (events & (A | D))
                    last_reset = frame + 1;
            }
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
        iteration = last_reset = 0;
        best = 0;
        registers[0x30/4] = 0;
        registers[0x70/4] = AUDIO_LINK_VERSION;
        if (!setjmp(finished))
            firmware_main();
    }
    return 0;
}
'''


class GameOverTimeoutTest(unittest.TestCase):
    def test_game_over_returns_to_menu_after_fifteen_idle_seconds(self):
        with tempfile.TemporaryDirectory() as directory:
            source, executable = Path(directory)/"game_over.c", Path(directory)/"game_over"
            source.write_text(HARNESS)
            subprocess.run(["cc", "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror",
                            "-I"+str(ROOT/"firmware"), "-I"+str(ROOT/"build"),
                            str(source), str(ROOT/"firmware/game_engine.c"),
                            "-o", str(executable)], check=True)
            subprocess.run([str(executable)], check=True, timeout=10)


if __name__ == "__main__":
    unittest.main()
