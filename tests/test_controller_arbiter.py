from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
RECEIVER = ROOT / "examples/espnow-counter/espnow-counter-rx"

PROGRAM = r'''
#include <cstdio>
#include "controller_arbiter.h"

static const uint8_t A[6] = {1, 1, 1, 1, 1, 1};
static const uint8_t B[6] = {2, 2, 2, 2, 2, 2};
static ControllerArbiter arbiter;

static void press(const char* name, const uint8_t* mac, unsigned buttons, unsigned now) {
    bool relevant = false;
    const int slot = arbiter.packet(mac, static_cast<uint8_t>(buttons), now, relevant);
    std::printf("%s slot=%d relevant=%d owner=%d out=%u\n", name, slot, relevant ? 1 : 0,
                arbiter.owner(), arbiter.output(now));
}

int main() {
    // Lobby: both controllers merge, no player yet.
    press("lobby-a-left", A, 0x1, 0);
    press("lobby-b-right", B, 0x4, 10);
    // B presses THRUST and starts the game.
    press("lobby-b-thrust", B, 0x2, 1000);
    std::printf("session-start released=%d\n", arbiter.setSession(true) ? 1 : 0);
    press("game-a-thrust", A, 0x2, 1050);
    press("game-b-left", B, 0x1, 1100);
    std::printf("game-out=%u\n", arbiter.output(1150));
    // The player's held buttons time out after 250 ms without packets.
    std::printf("game-timeout-out=%u\n", arbiter.output(1400));
    std::printf("session-end released=%d owner=%d\n",
                arbiter.setSession(false) ? 1 : 0, arbiter.owner());
    // Back in the lobby, A takes the next game.
    press("lobby-a-thrust", A, 0x2, 2000);
    arbiter.setSession(true);
    press("game2-b-thrust", B, 0x2, 2050);
    press("game2-a-right", A, 0x4, 2060);
    // Held THRUST repeats do not move ownership in the lobby.
    arbiter.setSession(false);
    press("lobby-b-thrust", B, 0x2, 3000);
    press("lobby-a-thrust-held", A, 0x2, 3010);
    press("lobby-a-thrust-held2", A, 0x2, 3100);
    // A session without a player (receiver restart mid-game) is claimed by THRUST.
    ControllerArbiter fresh;
    fresh.setSession(true);
    bool relevant = false;
    fresh.packet(A, 0x1, 4000, relevant);
    std::printf("unowned-left relevant=%d owner=%d\n", relevant ? 1 : 0, fresh.owner());
    fresh.packet(B, 0x2, 4010, relevant);
    std::printf("unowned-thrust owner=%d\n", fresh.owner());
    fresh.packet(A, 0x1, 4020, relevant);
    std::printf("unowned-after relevant=%d\n", relevant ? 1 : 0);
}
'''


class ControllerArbiterTest(unittest.TestCase):
    def test_first_thrust_owns_game(self):
        with tempfile.TemporaryDirectory() as directory:
            program = Path(directory) / "controller_arbiter_test"
            subprocess.run(
                ["c++", "-std=c++11", "-Wall", "-Wextra", "-Werror",
                 "-I", str(RECEIVER), "-x", "c++", "-", "-o", str(program)],
                input=PROGRAM, text=True, check=True,
            )
            result = subprocess.run(
                [str(program)], capture_output=True, text=True, check=True,
            )

        self.assertEqual(result.stdout.splitlines(), [
            "lobby-a-left slot=0 relevant=1 owner=-1 out=1",
            "lobby-b-right slot=1 relevant=1 owner=-1 out=5",
            "lobby-b-thrust slot=1 relevant=1 owner=1 out=2",
            "session-start released=0",
            "game-a-thrust slot=0 relevant=0 owner=1 out=2",
            "game-b-left slot=1 relevant=1 owner=1 out=1",
            "game-out=1",
            "game-timeout-out=0",
            "session-end released=1 owner=-1",
            "lobby-a-thrust slot=0 relevant=1 owner=0 out=2",
            "game2-b-thrust slot=1 relevant=0 owner=0 out=2",
            "game2-a-right slot=0 relevant=1 owner=0 out=4",
            "lobby-b-thrust slot=1 relevant=1 owner=1 out=2",
            "lobby-a-thrust-held slot=0 relevant=1 owner=0 out=2",
            "lobby-a-thrust-held2 slot=0 relevant=1 owner=0 out=2",
            "unowned-left relevant=1 owner=-1",
            "unowned-thrust owner=1",
            "unowned-after relevant=0",
        ])


if __name__ == "__main__":
    unittest.main()
