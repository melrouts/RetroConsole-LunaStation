from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
RECEIVER = ROOT / "examples/espnow-counter/espnow-counter-rx"

SOURCE = r'''
#include <algorithm>
#include <cassert>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <vector>
#include "game_audio.h"

typedef std::vector<int16_t> Samples;

// The original 16-bar score is 64 beats at 120 BPM.
static const size_t LOOP = 64 * 8000;
// Every level change used below has finished ramping by this frame.
static const size_t SETTLED = 20000;

static Samples render(GameAudio &audio, size_t frames) {
    Samples result(frames * 2, 0);
    audio.mix(result.data(), frames);
    for (size_t i = 0; i < frames; ++i) {
        assert(result[2 * i] == result[2 * i + 1]);
        assert(std::abs(static_cast<int>(result[2 * i])) <= StartupChime::PEAK);
    }
    return result;
}

static int peak(const Samples &samples, size_t firstFrame = 0) {
    int value = 0;
    for (size_t i = firstFrame * 2; i < samples.size(); ++i)
        value = std::max(value, std::abs(static_cast<int>(samples[i])));
    return value;
}

static double rms(const Samples &samples, size_t firstFrame, size_t lastFrame) {
    double sum = 0;
    for (size_t frame = firstFrame; frame < lastFrame; ++frame)
        sum += static_cast<double>(samples[frame * 2]) * samples[frame * 2];
    return std::sqrt(sum / (lastFrame - firstFrame));
}

static double tone_magnitude(const Samples &samples, size_t firstFrame,
                             size_t lastFrame, double frequency) {
    double real = 0;
    double imaginary = 0;
    for (size_t frame = firstFrame; frame < lastFrame; ++frame) {
        const double angle = 6.283185307179586 * frequency *
                             (frame - firstFrame) / 16000.0;
        real += samples[frame * 2] * std::cos(angle);
        imaginary -= samples[frame * 2] * std::sin(angle);
    }
    return 2.0 * std::sqrt(real * real + imaginary * imaginary) /
           (lastFrame - firstFrame);
}

// What one instance adds on top of another that was fed the same history.
static Samples difference(const Samples &a, const Samples &b) {
    assert(a.size() == b.size());
    Samples result(a.size());
    for (size_t i = 0; i < a.size(); ++i)
        result[i] = static_cast<int16_t>(a[i] - b[i]);
    return result;
}

static double gain(uint32_t value) {
    return static_cast<double>(value) / GameAudio::GAIN_ONE;
}

static void check_note(const Samples &samples, size_t first, size_t last, double expected) {
    std::vector<size_t> crossings;
    for (size_t frame = first + 1; frame < last; ++frame) {
        if (samples[(frame - 1) * 2] <= 0 && samples[frame * 2] > 0)
            crossings.push_back(frame);
    }
    assert(crossings.size() > 2);
    double measured = (crossings.size() - 1) * 16000.0 /
                      (crossings.back() - crossings.front());
    assert(std::abs(measured - expected) < 1.5);
}

static uint8_t frame_for(unsigned scene) {
    return static_cast<uint8_t>(0x40u | (scene << 3) | scene);
}

static void check_link() {
    struct Scene { unsigned code; GameAudioMode mode; bool thrust; };
    static const Scene scenes[] = {
        {0, GameAudioMode::Idle, false},
        {1, GameAudioMode::Flying, false},
        {2, GameAudioMode::Landed, false},
        {3, GameAudioMode::Crashed, false},
        {4, GameAudioMode::Attract, false},
        {5, GameAudioMode::Flying, true},
        {6, GameAudioMode::DemoFlying, false},
        {7, GameAudioMode::DemoFlying, true},
    };
    // The wire bytes older firmware already sent keep their meaning.
    assert(frame_for(0) == 0x40 && frame_for(1) == 0x49 && frame_for(2) == 0x52);
    assert(frame_for(3) == 0x5b && frame_for(4) == 0x64 && frame_for(5) == 0x6d);
    assert(frame_for(6) == 0x76 && frame_for(7) == 0x7f);

    GameAudioLink empty;
    assert(empty.state(0).mode == GameAudioMode::Idle);
    assert(!GameAudioLink::isFrame(0x82));
    assert(GameAudioLink::isSettingsFrame(0xdf));
    assert(!GameAudioLink::isSettingsFrame(0x40));
    assert(GameAudioLink::musicVolume(0xdf) == 3);
    assert(GameAudioLink::effectsVolume(0xdf) == 7);
    assert(!empty.accept(0x82, 10));
    assert(!empty.accept(0x65, 10));
    assert(empty.state(10).mode == GameAudioMode::Idle);

    for (const Scene &scene : scenes) {
        const uint8_t frame = frame_for(scene.code);
        assert(GameAudioLink::isFrame(frame));
        GameAudioLink link;
        assert(link.accept(frame, 1000));
        assert(link.state(1500).mode == scene.mode && link.state(1500).thrust == scene.thrust);
        // Any single flipped bit is rejected and must not refresh the timeout.
        for (unsigned bit = 0; bit < 8; ++bit)
            assert(!link.accept(static_cast<uint8_t>(frame ^ (1u << bit)), 1499));
        assert(link.state(1500).mode == scene.mode);
        assert(link.state(1501).mode == GameAudioMode::Idle);
    }

    GameAudioLink wrapped;
    assert(wrapped.accept(0x49, 0xffffff80u));
    assert(wrapped.state(0x50u).mode == GameAudioMode::Flying);
    assert(wrapped.state(0x200u).mode == GameAudioMode::Idle);

    assert(std::strcmp(GameAudioLink::modeName(GameAudioMode::Idle), "idle") == 0);
    assert(std::strcmp(GameAudioLink::modeName(GameAudioMode::Flying), "flying") == 0);
    assert(std::strcmp(GameAudioLink::modeName(GameAudioMode::Landed), "landed") == 0);
    assert(std::strcmp(GameAudioLink::modeName(GameAudioMode::Crashed), "crashed") == 0);
    assert(std::strcmp(GameAudioLink::modeName(GameAudioMode::Attract), "attract") == 0);
    assert(std::strcmp(GameAudioLink::modeName(GameAudioMode::DemoFlying), "demo") == 0);
}

static void check_demo() {
    GameAudioDemo demo;
    GameAudioState state{GameAudioMode::Idle, false};
    assert(!demo.next(state, 128));
    demo.start();
    assert(demo.next(state, 16000) && state.mode == GameAudioMode::Attract && !state.thrust);
    assert(demo.next(state, 16000) && state.mode == GameAudioMode::Attract);
    assert(demo.next(state, 16000) && state.mode == GameAudioMode::Flying && !state.thrust);
    assert(demo.next(state, 24000) && state.mode == GameAudioMode::Flying && state.thrust);
    assert(demo.next(state, 8000) && state.mode == GameAudioMode::Landed);
    assert(demo.next(state, 4000) && state.mode == GameAudioMode::Flying && !state.thrust);
    assert(demo.next(state, 12000) && state.mode == GameAudioMode::Crashed);
    assert(demo.next(state, 3200) && state.mode == GameAudioMode::Idle);
    assert(!demo.next(state, 128));

    demo.start();
    assert(demo.next(state, 60000) && state.mode == GameAudioMode::Attract);
    demo.start();
    assert(demo.next(state, 128) && state.mode == GameAudioMode::Attract);
}

static void check_music_levels() {
    GameAudio idle;
    assert(peak(render(idle, 256)) == 0);

    GameAudio menu, game, demo;
    menu.setState({GameAudioMode::Attract, false});
    game.setState({GameAudioMode::Flying, false});
    demo.setState({GameAudioMode::DemoFlying, false});
    const size_t frames = LOOP + SETTLED;
    const Samples menuMusic = render(menu, frames);
    const Samples gameMusic = render(game, frames);
    // The autopilot demo plays at the menu level, not the in-game one.
    assert(render(demo, frames) == menuMusic);

    const double menuGain = gain(GameAudio::MUSIC_MENU_GAIN);
    const double gameGain = gain(GameAudio::MUSIC_GAME_GAIN);
    // A little quieter during play, but still well within reach of the effects.
    assert(gameGain < menuGain && gameGain >= 0.5 * menuGain);
    // Six voices: bass, three chord tones, a pulsing arpeggio and a lead.
    assert(peak(menuMusic, SETTLED) <= 3100 * menuGain + 1);
    assert(peak(menuMusic, SETTLED) > 1000);
    assert(peak(gameMusic, SETTLED) <= 3100 * gameGain + 1);
    assert(peak(gameMusic, SETTLED) > 700);
    // The opening phrase has a distinct F5 lead over the D-minor pad and bass.
    assert(tone_magnitude(menuMusic, 20500, 23500, 698) > 250);
    assert(tone_magnitude(gameMusic, 20500, 23500, 698) > 150);

    // Both levels are the same track: only the gain differs.
    const double tolerance = 1 / menuGain + 1 / gameGain + 0.5;
    for (size_t frame = SETTLED; frame < frames; ++frame)
        assert(std::abs(menuMusic[2 * frame] / menuGain - gameMusic[2 * frame] / gameGain) <= tolerance);

    // The engine, measured alone, and the in-game music against it.
    GameAudio engine, demoEngine;
    engine.setState({GameAudioMode::Flying, true});
    demoEngine.setState({GameAudioMode::DemoFlying, true});
    const Samples gameMotor = render(engine, frames);
    const Samples demoMotor = render(demoEngine, frames);
    const Samples engineOnly = difference(gameMotor, gameMusic);
    const double engineRms = rms(engineOnly, SETTLED, frames);
    assert(engineRms > 500);
    assert(rms(gameMusic, SETTLED, frames) >= 0.4 * engineRms);
    // The engine does not depend on the music level, and nothing clips.
    assert(difference(demoMotor, menuMusic) == engineOnly);
    assert(peak(gameMotor) < GameAudio::MIX_PEAK);
    assert(peak(demoMotor) < GameAudio::MIX_PEAK);
}

static void check_level_change() {
    GameAudio steady, changed;
    steady.setState({GameAudioMode::Attract, false});
    changed.setState({GameAudioMode::Attract, false});
    assert(render(steady, 32000) == render(changed, 32000));

    // Main screen to game: the same track keeps going and is ducked smoothly.
    const size_t length = 48000;
    const double target = gain(GameAudio::MUSIC_GAME_GAIN) / gain(GameAudio::MUSIC_MENU_GAIN);
    changed.setState({GameAudioMode::Flying, false});
    Samples reference = render(steady, length);
    Samples changing = render(changed, length);
    size_t early = 0;
    for (size_t frame = 0; frame < length; ++frame) {
        if (std::abs(static_cast<int>(reference[2 * frame])) < 200)
            continue;
        const double ratio = static_cast<double>(changing[2 * frame]) / reference[2 * frame];
        assert(ratio <= 1.02 && ratio >= target - 0.02);
        if (frame < 160) {
            assert(ratio >= 0.95);
            ++early;
        }
        if (frame >= 4800)
            assert(std::abs(ratio - target) <= 0.02);
    }
    assert(early > 20);

    // Game to main screen: the level comes back up the same way.
    changed.setState({GameAudioMode::Attract, false});
    reference = render(steady, length);
    changing = render(changed, length);
    early = 0;
    for (size_t frame = 0; frame < 160; ++frame) {
        if (std::abs(static_cast<int>(reference[2 * frame])) < 200)
            continue;
        const double ratio = static_cast<double>(changing[2 * frame]) / reference[2 * frame];
        assert(ratio >= target - 0.02 && ratio <= target + 0.05);
        ++early;
    }
    assert(early > 20);
    const size_t ramp = (GameAudio::MUSIC_MENU_GAIN - GameAudio::MUSIC_GAME_GAIN) /
                        GameAudio::GAIN_STEP;
    assert(std::equal(changing.begin() + (ramp + 16) * 2, changing.end(),
                      reference.begin() + (ramp + 16) * 2));
}

static void check_idle_and_restart() {
    const size_t fade = GameAudio::MUSIC_MENU_GAIN / GameAudio::GAIN_STEP;

    GameAudio audio;
    audio.setState({GameAudioMode::Attract, false});
    render(audio, 40000);
    audio.setState({GameAudioMode::Idle, false});
    const Samples fading = render(audio, fade + 512);
    // The music fades out; it is neither cut off nor left playing.
    assert(peak(Samples(fading.begin(), fading.begin() + 1600 * 2)) > 500);
    assert(peak(fading, fade + 16) == 0);

    // After a full fade the track starts over, exactly like a fresh start.
    GameAudio fresh;
    fresh.setState({GameAudioMode::Attract, false});
    audio.setState({GameAudioMode::Attract, false});
    assert(render(audio, 40000) == render(fresh, 40000));

    // A short silence does not restart it.
    GameAudio blip, steady;
    blip.setState({GameAudioMode::Attract, false});
    steady.setState({GameAudioMode::Attract, false});
    render(blip, 40000);
    render(steady, 40000);
    blip.setState({GameAudioMode::Idle, false});
    render(blip, 1600);
    render(steady, 1600);
    blip.setState({GameAudioMode::Attract, false});
    const Samples resumed = render(blip, 20000);
    const Samples continuous = render(steady, 20000);
    assert(std::equal(resumed.begin() + 4000 * 2, resumed.end(), continuous.begin() + 4000 * 2));

    // Ending a flight that never played music stays silent.
    GameAudio never;
    never.setState({GameAudioMode::Landed, false});
    assert(peak(render(never, 8000)) == 0);
    never.setState({GameAudioMode::Crashed, false});
    assert(peak(render(never, 12000)) == 0);
}

static void check_engine() {
    GameAudio motor, plain;
    motor.setState({GameAudioMode::Flying, true});
    plain.setState({GameAudioMode::Flying, false});
    const Samples loud = render(motor, 4000);
    const Samples quiet = render(plain, 4000);
    assert(peak(difference(loud, quiet)) > 500);
    motor.setState({GameAudioMode::Flying, false});
    const Samples released = render(motor, GameAudio::FADE_FRAMES + 512);
    const Samples reference = render(plain, GameAudio::FADE_FRAMES + 512);
    assert(std::equal(released.begin() + GameAudio::FADE_FRAMES * 2, released.end(),
                      reference.begin() + GameAudio::FADE_FRAMES * 2));

    // Thrust only counts in flight; no state can start the engine elsewhere.
    GameAudio menuQuiet, menuThrust;
    menuQuiet.setState({GameAudioMode::Attract, false});
    menuThrust.setState({GameAudioMode::Attract, true});
    assert(render(menuQuiet, 20000) == render(menuThrust, 20000));
    GameAudio landedQuiet, landedThrust;
    landedQuiet.setState({GameAudioMode::Flying, false});
    landedThrust.setState({GameAudioMode::Flying, false});
    render(landedQuiet, 2000);
    render(landedThrust, 2000);
    landedQuiet.setState({GameAudioMode::Landed, false});
    landedThrust.setState({GameAudioMode::Landed, true});
    assert(render(landedQuiet, 8000) == render(landedThrust, 8000));
    GameAudio idleThrust;
    idleThrust.setState({GameAudioMode::Idle, true});
    assert(peak(render(idleThrust, 4000)) == 0);
}

static void check_effects() {
    // Landing from the game: two rising notes over the unchanged in-game music.
    GameAudio landing, steady;
    landing.setState({GameAudioMode::Flying, false});
    steady.setState({GameAudioMode::Flying, false});
    assert(render(landing, 500) == render(steady, 500));
    landing.setState({GameAudioMode::Landed, false});
    const Samples landed = difference(render(landing, 5000), render(steady, 5000));
    assert(peak(landed) > 3500);
    check_note(landed, 160, 1760, 660);
    check_note(landed, 1920 + 160, 1920 + 1760, 880);
    assert(peak(landed, 3840) == 0);
    landing.setState({GameAudioMode::Landed, false});
    assert(render(landing, 4000) == render(steady, 4000));

    // The autopilot demo ends with the same sound, over the menu-level music.
    GameAudio demoLanding, demoSteady;
    demoLanding.setState({GameAudioMode::DemoFlying, false});
    demoSteady.setState({GameAudioMode::DemoFlying, false});
    render(demoLanding, 20000);
    render(demoSteady, 20000);
    demoLanding.setState({GameAudioMode::Landed, false});
    assert(difference(render(demoLanding, 5000), render(demoSteady, 5000)) == landed);

    GameAudio crash, crashSteady;
    crash.setState({GameAudioMode::DemoFlying, false});
    crashSteady.setState({GameAudioMode::DemoFlying, false});
    render(crash, 20000);
    render(crashSteady, 20000);
    crash.setState({GameAudioMode::Crashed, false});
    const Samples crashMix = render(crash, 10000);
    const Samples crashed = difference(crashMix, render(crashSteady, 10000));
    assert(peak(crashed) > 500);
    assert(peak(crashed, 8800) == 0);
    assert(peak(crashMix) < GameAudio::MIX_PEAK);
    crash.setState({GameAudioMode::Crashed, false});
    assert(render(crash, 4000) == render(crashSteady, 4000));

    // Crashing under thrust silences the engine; the music carries on.
    GameAudio burning, coasting;
    burning.setState({GameAudioMode::Flying, true});
    coasting.setState({GameAudioMode::Flying, false});
    render(burning, 4000);
    render(coasting, 4000);
    burning.setState({GameAudioMode::Crashed, false});
    render(burning, 10000);
    render(coasting, 10000);
    assert(render(burning, 4000) == render(coasting, 4000));

    // No flight, no effect: the music simply carries on at its level.
    GameAudio plain, other;
    plain.setState({GameAudioMode::Attract, false});
    other.setState({GameAudioMode::Attract, false});
    render(plain, 3000);
    render(other, 3000);
    other.setState({GameAudioMode::Landed, false});
    assert(render(other, 8000) == render(plain, 8000));
    other.setState({GameAudioMode::Crashed, false});
    assert(render(other, 12000) == render(plain, 12000));

    // Resuming flight cancels a pending effect.
    GameAudio cancelled, flying;
    cancelled.setState({GameAudioMode::Flying, false});
    flying.setState({GameAudioMode::Flying, false});
    render(cancelled, 500);
    render(flying, 500);
    cancelled.setState({GameAudioMode::Landed, false});
    render(cancelled, 800);
    render(flying, 800);
    cancelled.setState({GameAudioMode::Flying, false});
    assert(render(cancelled, 6000) == render(flying, 6000));
}

static void check_mix() {
    const GameAudioMode modes[] = {GameAudioMode::Flying, GameAudioMode::DemoFlying};
    for (GameAudioMode mode : modes) {
        GameAudio mixed;
        StartupChime chime;
        mixed.setState({mode, true});
        chime.play();
        int16_t block[256];
        for (unsigned i = 0; i < 80; ++i) {
            chime.render(block, 128);
            mixed.mix(block, 128);
            for (size_t frame = 0; frame < 128; ++frame) {
                assert(block[2 * frame] == block[2 * frame + 1]);
                assert(std::abs(static_cast<int>(block[2 * frame])) <= StartupChime::PEAK);
            }
        }
    }
}

static void check_volume_controls() {
    GameAudio silentMusic;
    silentMusic.setVolumes(0, 7);
    silentMusic.setState({GameAudioMode::Attract, false});
    assert(peak(render(silentMusic, 24000)) == 0);

    GameAudio halfMusic, fullMusic;
    halfMusic.setVolumes(3, 7);
    fullMusic.setState({GameAudioMode::Attract, false});
    halfMusic.setState({GameAudioMode::Attract, false});
    const Samples full = render(fullMusic, 32000);
    const Samples half = render(halfMusic, 32000);
    assert(peak(half) > 0 && peak(half) < peak(full));

    GameAudio mutedEffects, fullEffects;
    mutedEffects.setVolumes(7, 0);
    mutedEffects.setState({GameAudioMode::Flying, false});
    fullEffects.setState({GameAudioMode::Flying, false});
    render(mutedEffects, 500);
    render(fullEffects, 500);
    mutedEffects.setState({GameAudioMode::Landed, false});
    fullEffects.setState({GameAudioMode::Landed, false});
    assert(peak(difference(render(mutedEffects, 6000),
                          render(fullEffects, 6000))) > 1000);
}

int main(int argc, char **argv) {
    const char *name = argc > 1 ? argv[1] : "";
    if (std::strcmp(name, "link") == 0) check_link();
    else if (std::strcmp(name, "demo") == 0) check_demo();
    else if (std::strcmp(name, "levels") == 0) check_music_levels();
    else if (std::strcmp(name, "level-change") == 0) check_level_change();
    else if (std::strcmp(name, "idle-restart") == 0) check_idle_and_restart();
    else if (std::strcmp(name, "engine") == 0) check_engine();
    else if (std::strcmp(name, "effects") == 0) check_effects();
    else if (std::strcmp(name, "mix") == 0) check_mix();
    else if (std::strcmp(name, "volume-controls") == 0) check_volume_controls();
    else return 2;
    return 0;
}
'''


class GameAudioTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory()
        cls.program = Path(cls.directory.name) / "game_audio_test"
        subprocess.run(
            ["c++", "-std=c++11", "-O2", "-Wall", "-Wextra", "-Werror",
             "-I", str(RECEIVER), "-x", "c++", "-", "-o", str(cls.program)],
            input=SOURCE, text=True, check=True,
        )

    @classmethod
    def tearDownClass(cls):
        cls.directory.cleanup()

    def check(self, name):
        subprocess.run([str(self.program), name], check=True, timeout=60)

    def test_link_decodes_every_scene_and_rejects_corrupt_frames(self):
        self.check("link")

    def test_demo_timeline_covers_menu_flight_and_effects(self):
        self.check("demo")

    def test_music_is_louder_on_menus_and_audible_over_the_engine_in_game(self):
        self.check("levels")

    def test_level_change_keeps_the_track_and_ramps_smoothly(self):
        self.check("level-change")

    def test_idle_fades_out_and_the_track_restarts_cleanly(self):
        self.check("idle-restart")

    def test_engine_follows_thrust_in_flight_only(self):
        self.check("engine")

    def test_landing_and_crash_effects_play_over_the_music(self):
        self.check("effects")

    def test_mix_with_startup_chime_stays_within_peak(self):
        self.check("mix")

    def test_music_and_effects_volume_controls(self):
        self.check("volume-controls")


if __name__ == "__main__":
    unittest.main()
