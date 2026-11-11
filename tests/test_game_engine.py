import ctypes
from fractions import Fraction
import json
import math
from pathlib import Path
import random
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
WORLD = 800 * 256
FAIL_PAD, FAIL_VERTICAL, FAIL_HORIZONTAL, FAIL_TILT = 1, 2, 4, 8
PADS = ((3, 6), (10, 12), (18, 20))
PAD_X = (38400, 93867, 162133)
OFF_PAD_X = 68000


class Flight(ctypes.Structure):
    _fields_ = [(name, ctypes.c_int32) for name in
                ("x", "y", "vx", "vy", "angle", "fuel", "x_remainder", "y_remainder",
                 "vx_remainder", "vy_remainder", "fuel_remainder", "thrusting")]


class Game(ctypes.Structure):
    _fields_ = [("ship", Flight), ("terrain", ctypes.c_int32 * 25),
                ("pad_start", ctypes.c_uint32 * 3), ("pad_end", ctypes.c_uint32 * 3)] + [
                    (name, ctypes.c_uint32) for name in ("random", "score", "level", "capsules", "outcome",
                                                         "gained", "cause")]


def expected_points(level, pad, vy, fuel):
    """Exact reference: 120*m + 100*(level-1) + 250*m*softness + 1.5*fuel, rounded half up."""
    multiplier = 1 << pad
    softness = min(max(48*256 - abs(vy), 0), 48*256)
    exact = (120*multiplier + 100*(level-1) + Fraction(250*multiplier*softness, 48*256) +
             Fraction(fuel*3, 2*256))
    return math.floor(exact + Fraction(1, 2))


def reference_ground(terrain, x):
    """The original 64-bit formula, with C truncation toward zero."""
    x = min(max(x, 0), WORLD)
    scaled = x * 24
    index = min(scaled // WORLD, 23)
    product = (terrain[index+1] - terrain[index]) * (scaled - index * WORLD)
    step = abs(product) // WORLD
    return terrain[index] + (-step if product < 0 else step)


class GameEngineTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory()
        library = Path(cls.temporary.name) / "game.dylib"
        subprocess.run(["cc", "-std=c11", "-Wall", "-Wextra", "-Werror", "-O2",
                        "-I", str(ROOT / "build"), "-shared", "-fPIC",
                        str(ROOT / "firmware/game_engine.c"), "-o", str(library)], check=True)
        cls.lib = ctypes.CDLL(str(library))
        cls.lib.game_new.argtypes = [ctypes.POINTER(Game), ctypes.c_uint32]
        cls.lib.game_level.argtypes = [ctypes.POINTER(Game)]
        cls.lib.game_physics.argtypes = [ctypes.POINTER(Game), ctypes.c_uint]
        cls.lib.game_touchdown.argtypes = [ctypes.POINTER(Game)]
        cls.lib.game_ground.argtypes = [ctypes.POINTER(Game), ctypes.c_int32]
        cls.lib.game_sine.argtypes = [ctypes.c_int32]

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def fresh(self, level=1):
        game = Game()
        self.lib.game_new(ctypes.byref(game), 42)
        game.level = level
        self.lib.game_level(ctypes.byref(game))
        return game

    def prepared(self, level=1, x=PAD_X[0], vy=0, vx=0, angle=0, fuel=300*256):
        """A ship resting exactly on flat ground, with three known pads."""
        game = self.fresh(level)
        for index in range(25):
            game.terrain[index] = 400*256
        for index, (start, end) in enumerate(PADS):
            game.pad_start[index] = start
            game.pad_end[index] = end
        game.ship.x, game.ship.y = x, (400-11)*256
        game.ship.vx, game.ship.vy, game.ship.angle, game.ship.fuel = vx, vy, angle, fuel
        return game

    def test_sine_table_accuracy_and_deterministic_terrain(self):
        maximum_error = max(abs(self.lib.game_sine(angle) -
                                math.sin(angle * math.tau / 65536) * 32767)
                            for angle in range(-32768, 32768, 31))
        self.assertLess(maximum_error, 4)
        for level in (1, 2, 6, 99):
            first, second = self.fresh(level), self.fresh(level)
            self.assertEqual(bytes(first), bytes(second))
            self.assertTrue(all(348*256 <= y <= 555*256 for y in first.terrain))
            for start, end in zip(first.pad_start, first.pad_end):
                self.assertGreater(end, start)
                self.assertEqual(len(set(first.terrain[start:end+1])), 1)
            self.assertEqual(self.lib.game_ground(ctypes.byref(first), 800*256), first.terrain[24])
            self.assertEqual(self.lib.game_ground(ctypes.byref(first), 0), first.terrain[0])

    @unittest.skipUnless((ROOT / "index.html").is_file(),
                         "The optional third-party browser reference is not included.")
    def test_trajectory_against_actual_javascript_update_function(self):
        masks = [0]*60 + [6]*20 + [2]*80 + [1]*20 + [0]*420
        node = r'''
const fs = require("fs");
const source = fs.readFileSync("index.html", "utf8");
const body = source.slice(source.indexOf("  function updateLander(dt)"),
                          source.indexOf("  function updateParticles(dt)"));
const names = ["LANDER_R", "ROT_SPEED", "THRUST", "MAX_TILT", "FUEL_BURN"];
const constants = names.map(name => {
  const found = source.match(new RegExp("var " + name + "\\s*=\\s*([^;]+);"));
  if (!found) throw new Error("Missing reference constant " + name);
  return "var " + name + " = " + found[1] + ";";
}).join("\n");
const step = new Function("lander", "keys", "gravity", "spawnParticles", "dt",
  constants + "\nfunction clamp(v, lo, hi) { return Math.min(hi, Math.max(lo, v)); }\n" +
  "var W = 800;\n" + body + "\nupdateLander(dt); return lander;");
let input = JSON.parse(fs.readFileSync(0, "utf8"));
let ship = {x: 400, y: 200, vx: -7, vy: 6, a: 0, fuel: 1200, landed: false, crashed: false};
let trace = input.map(mask => {
  ship = step(ship, {left: !!(mask&1), thrust: !!(mask&2), right: !!(mask&4)}, 21, () => {}, 1/60);
  return [ship.x, ship.y, ship.vx, ship.vy, ship.a, ship.fuel];
});
console.log(JSON.stringify(trace));
'''
        result = subprocess.run(["node", "-e", node], cwd=ROOT, input=json.dumps(masks),
                                text=True, capture_output=True, check=True)
        trace = json.loads(result.stdout)
        game = self.fresh()
        game.ship = Flight(x=400*256, y=200*256, vx=-7*256, vy=6*256, fuel=1200*256)
        for tick, (mask, expected) in enumerate(zip(masks, trace)):
            self.lib.game_physics(ctypes.byref(game), mask)
            actual = [game.ship.x/256, game.ship.y/256, game.ship.vx/256,
                      game.ship.vy/256, game.ship.angle*math.tau/65536, game.ship.fuel/256]
            for field, a, e, limit in zip(("x", "y", "vx", "vy", "angle", "fuel"),
                                         actual, expected, (0.25, 0.25, 0.1, 0.1, 0.002, 0.01)):
                error = min(abs(a-e), abs(abs(a-e)-800)) if field == "x" else abs(a-e)
                self.assertLessEqual(error, limit, (tick, field, a, e))

    def test_touchdown_exact_limits_one_unit_over_and_score(self):
        for level in (1, 2, 6, 99):
            limits = (self.lib.game_limit_vy(level), self.lib.game_limit_vx(level),
                      self.lib.game_limit_angle(level))
            for excessive in (None, "vy", "vx", "angle"):
                game = self.fresh(level)
                for index in range(25):
                    game.terrain[index] = 400*256
                game.pad_start[0] = 3
                game.pad_end[0] = 6
                game.ship.x = 150*256
                game.ship.y = (400-11)*256
                game.ship.vy, game.ship.vx, game.ship.angle = limits
                if excessive:
                    setattr(game.ship, excessive, getattr(game.ship, excessive) + 1)
                expected_score = math.floor(120 + 250*(1-abs(game.ship.vy)/(48*256)) +
                                            game.ship.fuel/256*1.5 + 100*(level-1) + 0.5)
                result = self.lib.game_touchdown(ctypes.byref(game))
                self.assertEqual(result, 2 if excessive else 1)
                self.assertEqual(game.capsules, 2 if excessive else 3)
                self.assertEqual(game.score, 0 if excessive else expected_score)
                self.assertEqual(game.gained, 0 if excessive else expected_score)
                self.assertEqual(game.cause, {None: 0, "vy": FAIL_VERTICAL, "vx": FAIL_HORIZONTAL,
                                              "angle": FAIL_TILT}[excessive])

    def test_pad_multipliers_double_each_pad_and_gained_matches_score(self):
        for level in (1, 4, 99):
            for pad, x in enumerate(PAD_X):
                for vy in (-10*256, 0, 20*256, 42*256):
                    game = self.prepared(level, x=x, vy=vy, fuel=777*256)
                    game.score = 1000
                    self.assertEqual(self.lib.game_touchdown(ctypes.byref(game)), 1)
                    expected = expected_points(level, pad, vy, 777*256)
                    self.assertEqual(game.gained, expected, (level, pad, vy))
                    self.assertEqual(game.score, 1000 + expected)
                    self.assertEqual(game.cause, 0)
        base = [self.prepared(x=x, vy=10*256) for x in PAD_X]
        for game in base:
            self.lib.game_touchdown(ctypes.byref(game))
        self.assertLess(base[0].gained, base[1].gained)
        self.assertLess(base[1].gained, base[2].gained)

    def test_failure_cause_bits_report_every_violated_check(self):
        for level in (1, 3, 99):
            vy = self.lib.game_limit_vy(level) + 1
            vx = self.lib.game_limit_vx(level) + 1
            angle = self.lib.game_limit_angle(level) + 1
            cases = (
                (dict(), 0),
                (dict(x=OFF_PAD_X), FAIL_PAD),
                (dict(vy=vy), FAIL_VERTICAL),
                (dict(vx=vx), FAIL_HORIZONTAL),
                (dict(vx=-vx), FAIL_HORIZONTAL),
                (dict(angle=angle), FAIL_TILT),
                (dict(angle=-angle), FAIL_TILT),
                (dict(vy=vy, angle=angle), FAIL_VERTICAL | FAIL_TILT),
                (dict(x=OFF_PAD_X, vx=vx), FAIL_PAD | FAIL_HORIZONTAL),
                (dict(x=OFF_PAD_X, vy=vy, vx=vx, angle=angle),
                 FAIL_PAD | FAIL_VERTICAL | FAIL_HORIZONTAL | FAIL_TILT),
            )
            for arguments, cause in cases:
                game = self.prepared(level, **arguments)
                game.score = 55
                result = self.lib.game_touchdown(ctypes.byref(game))
                self.assertEqual(game.cause, cause, (level, arguments))
                self.assertEqual(result, 2 if cause else 1)
                self.assertEqual(game.gained == 0, bool(cause))
                self.assertEqual(game.capsules, 2 if cause else 3)
                self.assertEqual(game.score == 55, bool(cause))

    def test_pad_edges_are_inclusive_and_exact(self):
        for pad, (start, end) in enumerate(PADS):
            first = -(-start * WORLD // 24)
            last = end * WORLD // 24
            for x, on_pad in ((first - 1, False), (first, True), (last, True), (last + 1, False)):
                game = self.prepared(x=x)
                self.lib.game_touchdown(ctypes.byref(game))
                self.assertEqual(game.cause, 0 if on_pad else FAIL_PAD, (pad, x))
                if on_pad:
                    self.assertEqual(game.gained, expected_points(1, pad, 0, 300*256))
        for x in (-5*256, WORLD + 5*256):
            game = self.prepared(x=x)
            self.lib.game_touchdown(ctypes.byref(game))
            self.assertEqual(game.cause, FAIL_PAD)

    def test_result_is_cleared_for_the_next_level_and_new_game(self):
        game = self.prepared(x=OFF_PAD_X, vx=9999)
        self.lib.game_touchdown(ctypes.byref(game))
        self.assertNotEqual(game.cause, 0)
        self.lib.game_level(ctypes.byref(game))
        self.assertEqual((game.gained, game.cause, game.outcome), (0, 0, 0))
        game = self.prepared(vy=5*256)
        self.lib.game_touchdown(ctypes.byref(game))
        self.assertGreater(game.gained, 0)
        self.lib.game_new(ctypes.byref(game), 7)
        self.assertEqual((game.gained, game.cause, game.score), (0, 0, 0))

    def test_game_new_defines_every_byte_of_the_state(self):
        dirty = Game.from_buffer_copy(bytes([0xa5]) * ctypes.sizeof(Game))
        clean = Game()
        self.lib.game_new(ctypes.byref(dirty), 42)
        self.lib.game_new(ctypes.byref(clean), 42)
        self.assertEqual(bytes(dirty), bytes(clean))

    def test_ground_interpolation_matches_the_64_bit_reference(self):
        generator = random.Random(2026)
        boundaries = [value for index in range(25) for value in
                      range(-(-index * WORLD // 24) - 3, -(-index * WORLD // 24) + 4)]
        positions = sorted(set(range(-300, WORLD + 301, 61)) | set(boundaries))
        for terrain in ([generator.randint(348*256, 555*256) for _ in range(25)] for _ in range(24)):
            game = self.fresh(generator.choice((1, 3, 7, 99)))
            for index, value in enumerate(terrain):
                game.terrain[index] = value
            for x in positions:
                self.assertEqual(self.lib.game_ground(ctypes.byref(game), x),
                                 reference_ground(terrain, x), x)
        extremes = [348*256 if index % 2 else 555*256 for index in range(25)]
        game = self.fresh()
        for index, value in enumerate(extremes):
            game.terrain[index] = value
        for x in positions:
            self.assertEqual(self.lib.game_ground(ctypes.byref(game), x),
                             reference_ground(extremes, x), x)

    def test_fuel_wrap_ceiling_and_frozen_outcome(self):
        game = self.fresh()
        game.ship.x = 0
        game.ship.vx = -60*256
        game.ship.y = 11*256
        game.ship.vy = -60*256
        self.lib.game_physics(ctypes.byref(game), 2)
        self.assertGreater(game.ship.x, 799*256 - 1)
        self.assertEqual(game.ship.y, 11*256)
        self.assertEqual(game.ship.vy, 0)
        for _ in range(1000):
            self.lib.game_physics(ctypes.byref(game), 2)
        self.assertEqual(game.ship.fuel, 0)
        game.outcome = 2
        before = bytes(game.ship)
        self.lib.game_physics(ctypes.byref(game), 7)
        self.assertEqual(bytes(game.ship), before)


if __name__ == "__main__":
    unittest.main()
