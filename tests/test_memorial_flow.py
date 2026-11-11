"""Execute the real game loop natively with deterministic frame/MMIO input."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
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
static jmp_buf finished;
static unsigned scenario, stage, ticks, entered_at, observed, last_age;
static const unsigned sequence[] = { MAIN_SCREEN, LUNA_MEMORIAL, APOLLO_MEMORIAL, DEMO, MAIN_SCREEN };
static volatile uint32_t *sim_mmio(unsigned offset)
{
    if (offset == 0x14) {
        ++registers[offset/4];
        if (registers[0x30/4] == 7) {
            if (state != observed) {
                if (state == PLAY) {
                    assert(scenario && stage == scenario);
                    assert(best == 0);
                    longjmp(finished, 1);
                }
                assert(stage < 4 && state == sequence[stage+1]);
                assert(last_age == 899);
                assert(ticks-entered_at >= 900);
                entered_at = ticks;
                observed = state;
                ++stage;
                if (!scenario && stage == 4) {
                    assert(best == 0);
                    longjmp(finished, 1);
                }
            }
            last_age = age;
            ++ticks;
            assert(ticks < 8000);
        }
    } else if (offset == 4) {
        registers[1] = scenario && stage == scenario ? 2 : 0;
    }
    return &registers[offset/4];
}
int main(void)
{
    game_new(&game, 42);
    for (unsigned i = 0; i < 25; ++i) game.terrain[i] = 300*256;
    game.ship.y = (300-11-123)*256;
    game.ship.vx = 3*256; game.ship.vy = 4*256;
    uint32_t data = telemetry();
    assert(((data >> 8) & 0xfff) == 5);
    assert(((data >> 20) & 15) == 3);
    assert((registers[0x48/4] >> 28) == 2);
    assert((registers[0x40/4] >> 28) == 1);
    assert((data & 12) == 0);
    const int velocities[8][2] = {{0,-10},{10,-10},{10,0},{10,10},
                                  {0,10},{-10,10},{-10,0},{-10,-10}};
    for (unsigned i = 0; i < 8; ++i) {
        game.ship.vx = velocities[i][0]*256;
        game.ship.vy = velocities[i][1]*256;
        telemetry();
        unsigned xy = registers[0x40/4];
        assert((((xy >> 26) & 3) | (((xy >> 15) & 1) << 2)) == i);
    }
    game.ship.vx = game_limit_vx(1)*3/4; game.ship.vy = 0;
    assert((telemetry() & 12) == 4);
    game.ship.vx = game_limit_vx(1);
    assert((telemetry() & 12) == 4);
    ++game.ship.vx;
    assert((telemetry() & 12) == 8);
    game.ship.vx = 0; game.ship.vy = 2048*256;
    assert(((telemetry() >> 8) & 0xfff) == 0x999);
    game.ship.vx = game.ship.vy = 0;
    assert(((telemetry() >> 8) & 0xfff) == 0);
    game.ship.y = 400*256;
    assert(((telemetry() >> 20) & 15) == 0);
    registers[0x1c/4] = registers[0x20/4] = 1;
    for (scenario = 0; scenario < 3; ++scenario) {
        stage = ticks = entered_at = last_age = 0; observed = MAIN_SCREEN;
        registers[0x70/4] = AUDIO_LINK_VERSION;
        if (!setjmp(finished))
            firmware_main();
    }
    return 0;
}
'''


class MemorialFlowTest(unittest.TestCase):
    def test_idle_luna_apollo_demo_and_start_interrupts_each_card(self):
        with tempfile.TemporaryDirectory() as directory:
            source, executable = Path(directory)/"flow.c", Path(directory)/"flow"
            source.write_text(HARNESS)
            subprocess.run(["cc", "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror",
                            "-I"+str(ROOT/"firmware"), "-I"+str(ROOT/"build"),
                            str(source), str(ROOT/"firmware/game_engine.c"),
                            "-o", str(executable)], check=True)
            subprocess.run([str(executable)], check=True, timeout=10)


if __name__ == "__main__":
    unittest.main()
