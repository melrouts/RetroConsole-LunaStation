from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
TRANSMITTER = ROOT / "examples/espnow-counter/espnow-counter-tx"


class ControllerPowerTest(unittest.TestCase):
    def test_debounce_menu_transitions_and_wake(self):
        source = r'''
#include <cassert>
#include "controller_power.h"
using namespace ControllerPower;

void enter(State& state, uint32_t start) {
    assert(state.update(MENU, start) == 0);
    assert(state.update(MENU, start + MENU_HOLD_MS - 1) == 0);
    assert(state.mode() == Mode::Active);
    assert(state.update(MENU, start + MENU_HOLD_MS) == 0);
    assert(state.mode() == Mode::Entering);
    for (uint8_t frame = 0; frame < 4; ++frame) {
        assert(state.frame(start + MENU_HOLD_MS + frame * FRAME_MS) == frame);
    }
    state.update(MENU, start + MENU_HOLD_MS + TRANSITION_MS);
    assert(state.mode() == Mode::WaitRelease);
    assert(!state.shouldSleep(MENU, MENU));
    assert(!state.shouldSleep(0, MENU));
    assert(!state.shouldSleep(1, 0));
    assert(state.shouldSleep(0, 0));
}

int main() {
    Buttons buttons;
    assert(buttons.update(0xf, 0) == 0);
    assert(buttons.update(0xf, DEBOUNCE_MS - 1) == 0);
    assert(buttons.update(0xf, DEBOUNCE_MS) == 0xf);
    assert(buttons.update(0, 30) == 0xf);
    assert(buttons.update(0xf, 35) == 0xf);
    assert(buttons.update(0, 40) == 0xf);
    assert(buttons.update(0, 60) == 0);

    State shortPress;
    assert(shortPress.update(1 | MENU, 100) == 1);
    assert(shortPress.update(4 | MENU, 150) == 4);
    assert(shortPress.update(4, 200) == (4 | MENU));
    assert(shortPress.update(0, 299) == MENU);
    assert(shortPress.update(0, 300) == 0);
    assert(shortPress.mode() == Mode::Active);

    // Unsigned timer arithmetic must survive millis() rollover.
    State rollover;
    enter(rollover, UINT32_MAX - 500);
    State pulseRollover;
    assert(pulseRollover.update(MENU, UINT32_MAX - 30) == 0);
    assert(pulseRollover.update(0, UINT32_MAX - 10) == MENU);
    assert(pulseRollover.update(0, 50) == MENU);
    assert(pulseRollover.update(0, 100) == 0);

    for (uint8_t wakeBit = 1; wakeBit <= MENU; wakeBit <<= 1) {
        State state;
        enter(state, 100);
        state.wake(10000);
        assert(state.mode() == Mode::Waking);
        assert(state.update(wakeBit, 10020) == 0);
        assert(state.update(wakeBit, 10000 + TRANSITION_MS) == 0);
        assert(state.mode() == Mode::WaitWakeRelease);
        state.released(0, wakeBit);
        assert(state.mode() == Mode::WaitWakeRelease);
        state.released(wakeBit, 0);
        assert(state.mode() == Mode::WaitWakeRelease);
        assert(state.update(0xf, 15000) == 0);
        state.released(0, 0);
        assert(state.mode() == Mode::Active);
        assert(state.update(0, 15001) == 0);
        assert(state.update(7, 15002) == 7);
        // A wake using Menu must not become a short Menu pulse or re-sleep.
        assert(state.update(0, 15003) == 0);
        enter(state, 16000);
    }

    // Exercise the same raw -> debounce -> local control pipeline as loop().
    for (uint8_t wakeBit = 1; wakeBit <= MENU; wakeBit <<= 1) {
        State state;
        state.wake(0);
        Buttons wakeButtons;
        for (uint32_t now = 0; now <= 3000; ++now) {
            const uint8_t held = wakeButtons.update(wakeBit, now);
            assert(state.update(held, now) == 0);
            state.released(wakeBit, held);
        }
        for (uint32_t now = 3001; now < 3021; ++now) {
            const uint8_t held = wakeButtons.update(0, now);
            assert(state.update(held, now) == 0);
            state.released(0, held);
            assert(state.mode() != Mode::Active);
        }
        const uint8_t held = wakeButtons.update(0, 3021);
        assert(state.update(held, 3021) == 0);
        state.released(0, held);
        assert(state.mode() == Mode::Active);
        assert(state.update(0, 3022) == 0);
    }

    State bounce;
    Buttons debounced;
    bounce.update(debounced.update(MENU, 0), 0);
    bounce.update(debounced.update(0, 10), 10);
    assert(bounce.update(debounced.update(0, 30), 30) == 0);
    assert(bounce.mode() == Mode::Active);
}
'''
        build = ROOT / "build"
        build.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=build) as directory:
            program = Path(directory) / "controller_power_test"
            subprocess.run(
                ["c++", "-std=c++11", "-Wall", "-Wextra", "-Werror",
                 "-I", str(TRANSMITTER), "-x", "c++", "-", "-o", str(program)],
                input=source, text=True, check=True,
            )
            subprocess.run([str(program)], check=True)


if __name__ == "__main__":
    unittest.main()
