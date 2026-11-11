"""Check the real game's audio state mapping and the music scenes it publishes."""
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
HARNESS = r'''
#include <assert.h>
#include <stdint.h>
#include "mmio.h"
static uint32_t registers[64], terrain[640];
static volatile uint32_t *sim_mmio(unsigned offset) { return &registers[offset / 4]; }
#undef MMIO32
#define MMIO32(offset) (*sim_mmio(offset))
#undef TERRAIN_COLUMN
#define TERRAIN_COLUMN(index) terrain[index]
#define main firmware_main
#include "game.c"
#undef main

static void check(unsigned expected)
{
    publish_audio();
    assert(registers[0x70 / 4] == expected);
}

int main(void)
{
    /* These numbers are the wire contract with the ESP32 decoder. */
    assert(GAME_AUDIO_IDLE == 0 && GAME_AUDIO_FLYING == 1);
    assert(GAME_AUDIO_LANDED == 2 && GAME_AUDIO_CRASHED == 3);
    assert(GAME_AUDIO_ATTRACT == 4 && GAME_AUDIO_FLYING_THRUST == 5);
    assert(GAME_AUDIO_DEMO == 6 && GAME_AUDIO_DEMO_THRUST == 7);

    state = MAIN_SCREEN;
    check(GAME_AUDIO_ATTRACT);
    state = LUNA_MEMORIAL;
    check(GAME_AUDIO_ATTRACT);
    state = APOLLO_MEMORIAL;
    check(GAME_AUDIO_ATTRACT);
    state = PLAY;
    check(GAME_AUDIO_FLYING);
    game.ship.thrusting = 1;
    check(GAME_AUDIO_FLYING_THRUST);
    state = EXIT_CONFIRM;
    check(GAME_AUDIO_FLYING);
    state = LANDED;
    check(GAME_AUDIO_LANDED);
    state = CRASHED;
    check(GAME_AUDIO_CRASHED);
    state = GAME_OVER;
    check(GAME_AUDIO_CRASHED);
    state = DEMO;
    game.outcome = 0;
    check(GAME_AUDIO_DEMO_THRUST);
    game.ship.thrusting = 0;
    check(GAME_AUDIO_DEMO);
    game.outcome = 1;
    check(GAME_AUDIO_LANDED);
    game.outcome = 2;
    check(GAME_AUDIO_CRASHED);
    return 0;
}
'''

# Runs the real main loop: the attract cycle untouched, then a scripted session.
FLOW_HARNESS = r'''
#include <assert.h>
#include <setjmp.h>
#include <stdint.h>
#include "mmio.h"
static uint32_t registers[64], terrain[640];
static volatile uint32_t *sim_mmio(unsigned offset);
static jmp_buf returned_to_boot;
static void fake_boot(void) { longjmp(returned_to_boot, 1); }
#define BOOT_MENU_ENTRY ((uintptr_t)fake_boot)
#undef MMIO32
#define MMIO32(offset) (*sim_mmio(offset))
#undef TERRAIN_COLUMN
#define TERRAIN_COLUMN(index) terrain[index]
#define main firmware_main
#include "game.c"
#undef main

static jmp_buf finished;
static unsigned scenario, frames, event, changes, last_state;
static unsigned seen[9];

static void on_frame(void)
{
    unsigned audio = registers[0x70 / 4];
    assert(audio < 8);
    seen[state] |= 1u << audio;
    if (state == MAIN_SCREEN || state == LUNA_MEMORIAL || state == APOLLO_MEMORIAL)
        assert(audio == GAME_AUDIO_ATTRACT);
    else if (state == DEMO)
        assert(audio == GAME_AUDIO_DEMO || audio == GAME_AUDIO_DEMO_THRUST ||
               audio == GAME_AUDIO_LANDED || audio == GAME_AUDIO_CRASHED);
    else if (state == PLAY)
        assert(audio == (game.ship.thrusting ? GAME_AUDIO_FLYING_THRUST : GAME_AUDIO_FLYING));
    else if (state == EXIT_CONFIRM)
        assert(audio == GAME_AUDIO_FLYING);
    else if (state == LANDED)
        assert(audio == GAME_AUDIO_LANDED);
    else
        assert(audio == GAME_AUDIO_CRASHED);

    if (state != last_state) {
        last_state = state;
        ++changes;
    }
    event = 0;
    registers[0] = 0;
    if (scenario == 0) {
        /* Idle: main screen, Luna 9, Apollo 11, autopilot demo, main screen again. */
        if (changes == 4)
            longjmp(finished, 1);
        assert(frames < 6000);
    } else if (scenario == 1) {
        /* Start, fly, hold thrust, pause with the engine on, resume, leave. */
        if (frames == 10)
            event = 2;
        if (frames >= 20 && frames < 30)
            registers[0] = 2;
        if (frames >= 35 && frames <= 40)
            registers[0] = 2;
        if (frames == 40)
            event = 8;
        if (frames == 50)
            event = 8;
        if (frames >= 60 && frames < 70)
            registers[0] = 2;
        if (frames == 80)
            event = 8;
        if (frames == 90)
            event = 2;
        if (frames == 100)
            longjmp(finished, 1);
    }
    ++frames;
}

static volatile uint32_t *sim_mmio(unsigned offset)
{
    if (offset == 0x14)
        ++registers[offset / 4];
    else if (offset == 4)
        registers[1] = event;
    else if (offset == 0x5c)
        on_frame();
    return &registers[offset / 4];
}

int main(void)
{
    registers[0x1c / 4] = registers[0x20 / 4] = 1;
    for (scenario = 0; scenario < 2; ++scenario) {
        frames = changes = 0;
        event = 0;
        last_state = MAIN_SCREEN;
        registers[0x70 / 4] = AUDIO_LINK_VERSION;
        if (!setjmp(finished))
            firmware_main();
    }
    assert(console_return_requested(MAIN_SCREEN, 8));
    assert(!console_return_requested(PLAY, 8));
    assert(!console_return_requested(MAIN_SCREEN, 2));
    if (!setjmp(returned_to_boot))
        return_to_console_menu();
    /* The idle run visits every attract scene and the autopilot demo with music. */
    assert(seen[MAIN_SCREEN] == 1u << GAME_AUDIO_ATTRACT);
    assert(seen[LUNA_MEMORIAL] == 1u << GAME_AUDIO_ATTRACT);
    assert(seen[APOLLO_MEMORIAL] == 1u << GAME_AUDIO_ATTRACT);
    assert(seen[DEMO] & 1u << GAME_AUDIO_DEMO);
    assert(!(seen[DEMO] & (1u << GAME_AUDIO_FLYING | 1u << GAME_AUDIO_FLYING_THRUST)));
    /* The played session uses the in-game scenes, also while paused. */
    assert(seen[PLAY] == (1u << GAME_AUDIO_FLYING | 1u << GAME_AUDIO_FLYING_THRUST));
    assert(seen[EXIT_CONFIRM] == 1u << GAME_AUDIO_FLYING);
    return 0;
}
'''


class GameAudioControlTest(unittest.TestCase):
    def build_and_run(self, name, source_text):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / (name + ".c")
            executable = Path(directory) / name
            source.write_text(source_text)
            subprocess.run(
                ["cc", "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror",
                 "-I" + str(ROOT / "firmware"), "-I" + str(ROOT / "build"),
                 str(source), str(ROOT / "firmware/game_engine.c"), "-o", str(executable)],
                check=True,
            )
            subprocess.run([str(executable)], check=True, timeout=10)

    def test_game_states_and_demo_outcomes(self):
        self.build_and_run("game_audio_control", HARNESS)

    def test_real_loop_publishes_music_scenes(self):
        self.build_and_run("game_audio_flow", FLOW_HARNESS)


if __name__ == "__main__":
    unittest.main()
