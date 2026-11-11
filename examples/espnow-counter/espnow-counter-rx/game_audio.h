#ifndef GAME_AUDIO_H
#define GAME_AUDIO_H

#include <stddef.h>
#include <stdint.h>

#include "game_audio_link.h"
#include "startup_chime.h"

class GameAudio {
public:
    static constexpr uint32_t SAMPLE_RATE = StartupChime::SAMPLE_RATE;
    static constexpr int16_t MIX_PEAK = StartupChime::PEAK;
    static constexpr uint32_t FADE_FRAMES = SAMPLE_RATE * 8 / 1000;
    // Music gain is a fixed-point factor (GAIN_ONE = the level of the synthesized track).
    // The menu level is used on the main screen, memorials and the autopilot demo; the
    // lower in-game level leaves room for the engine and landing/crash effects.
    static constexpr uint32_t GAIN_ONE = 1u << 16;
    static constexpr uint32_t MUSIC_MENU_GAIN = GAIN_ONE * 29 / 20;
    static constexpr uint32_t MUSIC_GAME_GAIN = GAIN_ONE * 13 / 10;
    // Level changes are ramped, not stepped: GAIN_ONE takes half a second.
    static constexpr uint32_t GAIN_STEP = GAIN_ONE / (SAMPLE_RATE / 2);
    static_assert(MIX_PEAK >= 0, "Audio peak must be non-negative");
    static_assert(MUSIC_GAME_GAIN < MUSIC_MENU_GAIN && MUSIC_MENU_GAIN <= 2 * GAIN_ONE,
                  "Music levels must be ordered and keep the sample math within 32 bits");

    void setVolumes(uint8_t music, uint8_t effects) {
        musicVolume_ = music > 7 ? 7 : music;
        effectsVolume_ = effects > 7 ? 7 : effects;
    }

    void setState(GameAudioState state) {
        if (state.mode != mode_) {
            if (isFlight(mode_) && state.mode == GameAudioMode::Landed) {
                effect_ = Effect::Landing;
                effectFrame_ = 0;
            } else if (isFlight(mode_) && state.mode == GameAudioMode::Crashed) {
                effect_ = Effect::Crash;
                effectFrame_ = 0;
                crashFilter_ = 0;
            } else if (state.mode != GameAudioMode::Landed &&
                       state.mode != GameAudioMode::Crashed) {
                effect_ = Effect::None;
            }
            setMusicTarget(state.mode);
            mode_ = state.mode;
        }
        thrust_ = isFlight(state.mode) && state.thrust;
    }

    void mix(int16_t* stereo, size_t frames) {
        for (size_t i = 0; i < frames; ++i) {
            musicGain_ = approach(musicGain_, musicTarget_);
            engineEnvelope_ = fade(engineEnvelope_, thrust_);
            int32_t sample = 0;
            if (musicGain_ != 0) {
                sample += musicSample() * static_cast<int32_t>(musicGain_) /
                          static_cast<int32_t>(GAIN_ONE) * musicVolume_ / 7;
            }
            if (engineEnvelope_ != 0) {
                engineFilter_ += (noise() - engineFilter_) / 6;
                int32_t engine = engineFilter_ * 5000 / 32768;
                sample += engine * static_cast<int32_t>(engineEnvelope_) /
                          static_cast<int32_t>(FADE_FRAMES) * effectsVolume_ / 7;
            }
            sample += effectSample() * effectsVolume_ / 7;
            sample = sample * static_cast<int32_t>(MIX_PEAK) / 7500;
            stereo[2 * i] = limit(static_cast<int32_t>(stereo[2 * i]) + sample);
            stereo[2 * i + 1] = limit(static_cast<int32_t>(stereo[2 * i + 1]) + sample);
        }
    }

private:
    enum class Effect : uint8_t { None, Landing, Crash };
    static constexpr uint32_t BEAT_FRAMES = SAMPLE_RATE / 2;
    static constexpr uint32_t STEP_FRAMES = BEAT_FRAMES / 2;
    static constexpr uint32_t ARP_FRAMES = BEAT_FRAMES / 4;
    static constexpr uint32_t MUSIC_BEATS = 64;
    static constexpr uint32_t PAD_FADE_FRAMES = SAMPLE_RATE * 50 / 1000;
    static constexpr uint32_t LAND_NOTE_FRAMES = SAMPLE_RATE * 120 / 1000;
    static constexpr uint32_t CRASH_FRAMES = SAMPLE_RATE * 550 / 1000;

    static bool isFlight(GameAudioMode mode) {
        return mode == GameAudioMode::Flying || mode == GameAudioMode::DemoFlying;
    }

    static uint32_t fade(uint32_t value, bool on) {
        if (on && value < FADE_FRAMES) {
            return value + 1;
        }
        if (!on && value != 0) {
            return value - 1;
        }
        return value;
    }

    static uint32_t approach(uint32_t value, uint32_t target) {
        if (value + GAIN_STEP <= target) {
            return value + GAIN_STEP;
        }
        if (value >= target + GAIN_STEP) {
            return value - GAIN_STEP;
        }
        return target;
    }

    // Landed and Crashed carry no music level of their own: the music keeps
    // playing at the level of the flight that ended, or stays off.
    void setMusicTarget(GameAudioMode mode) {
        uint32_t target = musicTarget_;
        if (mode == GameAudioMode::Idle) {
            target = 0;
        } else if (mode == GameAudioMode::Flying) {
            target = MUSIC_GAME_GAIN;
        } else if (mode == GameAudioMode::Attract || mode == GameAudioMode::DemoFlying) {
            target = MUSIC_MENU_GAIN;
        }
        if (target != 0 && musicGain_ == 0) {
            musicFrame_ = 0;
            bassPhase_ = 0;
            leadPhase_ = 0;
            arpPhase_ = 0;
            padPhase_[0] = padPhase_[1] = padPhase_[2] = 0;
        }
        musicTarget_ = target;
    }

    static uint32_t increment(uint32_t frequency) {
        return static_cast<uint32_t>((static_cast<uint64_t>(frequency) << 32) / SAMPLE_RATE);
    }

    static uint32_t noteIncrement(uint8_t note) {
        static constexpr uint16_t semitones[] = {
            262, 277, 294, 311, 330, 349, 370, 392, 415, 440, 466, 494,
        };
        int pitch = static_cast<int>(note) - 60;
        int octave = pitch / 12;
        int semitone = pitch % 12;
        if (semitone < 0) {
            semitone += 12;
            --octave;
        }
        uint32_t frequency = semitones[semitone];
        if (octave > 0) {
            frequency <<= octave;
        } else if (octave < 0) {
            frequency >>= -octave;
        }
        return increment(frequency);
    }

    static int32_t triangle(uint32_t phase) {
        const int32_t position = static_cast<int32_t>(phase >> 16);
        return position < 32768 ? position * 2 - 32768 : 98303 - position * 2;
    }

    static int16_t limit(int32_t value) {
        if (value > MIX_PEAK) {
            return MIX_PEAK;
        }
        if (value < -MIX_PEAK) {
            return -MIX_PEAK;
        }
        return static_cast<int16_t>(value);
    }

    int32_t noise() {
        random_ ^= random_ << 13;
        random_ ^= random_ >> 17;
        random_ ^= random_ << 5;
        return static_cast<int32_t>(random_ >> 16) - 32768;
    }

    int32_t musicSample() {
        // Original 16-bar D-minor progression; each chord lasts two bars.
        static constexpr uint8_t roots[] = {50, 46, 41, 48, 43, 46, 50, 45};
        static constexpr uint8_t thirds[] = {3, 4, 4, 4, 3, 4, 3, 4};
        // MIDI note numbers in eighth-note steps; zero is a rest.
        static constexpr uint8_t melody[] = {
            74, 0, 77, 81, 79, 77, 74, 0, 72, 74, 77, 0, 76, 74, 72, 69,
            70, 0, 74, 77, 76, 74, 70, 0, 69, 70, 74, 0, 72, 70, 69, 65,
            69, 0, 72, 77, 76, 72, 69, 0, 67, 69, 72, 0, 74, 72, 69, 67,
            72, 0, 76, 79, 77, 76, 72, 0, 69, 72, 76, 0, 74, 72, 69, 67,
            67, 0, 70, 74, 72, 70, 67, 0, 65, 67, 70, 0, 69, 67, 65, 62,
            70, 74, 77, 0, 81, 79, 77, 74, 70, 0, 74, 77, 76, 74, 70, 0,
            74, 77, 81, 84, 82, 81, 77, 74, 76, 77, 81, 0, 79, 77, 74, 72,
            73, 0, 76, 81, 79, 76, 73, 69, 71, 73, 76, 0, 78, 76, 73, 69,
        };

        const uint32_t beat = musicFrame_ / BEAT_FRAMES;
        const uint32_t beatPosition = musicFrame_ % BEAT_FRAMES;
        const uint32_t step = musicFrame_ / STEP_FRAMES;
        const uint32_t stepPosition = musicFrame_ % STEP_FRAMES;
        const uint32_t arpStep = (musicFrame_ / ARP_FRAMES) % 4;
        const uint32_t chord = (beat / 8) % 8;
        if (beatPosition == 0) {
            const uint8_t bassNote = static_cast<uint8_t>(
                roots[chord] - 12 + ((beat % 4) == 2 ? 7 : 0));
            bassIncrement_ = noteIncrement(bassNote);
        }
        if ((beat % 8) == 0 && beatPosition == 0) {
            padIncrement_[0] = noteIncrement(static_cast<uint8_t>(roots[chord] + 12));
            padIncrement_[1] = noteIncrement(
                static_cast<uint8_t>(roots[chord] + 12 + thirds[chord]));
            padIncrement_[2] = noteIncrement(static_cast<uint8_t>(roots[chord] + 19));
        }
        if (stepPosition == 0) {
            leadIncrement_ = melody[step % (MUSIC_BEATS * 2)] == 0
                                 ? 0
                                 : noteIncrement(melody[step % (MUSIC_BEATS * 2)]);
            leadPhase_ = 0;
        }
        if (musicFrame_ % ARP_FRAMES == 0) {
            const uint8_t arpNote = static_cast<uint8_t>(
                roots[chord] + 24 + ((arpStep == 1 || arpStep == 3) ? 7 :
                                     (arpStep == 2 ? thirds[chord] : 0)));
            arpIncrement_ = noteIncrement(arpNote);
            arpPhase_ = 0;
        }

        uint32_t bassEnvelope = beatPosition < FADE_FRAMES ? beatPosition : FADE_FRAMES;
        const uint32_t bassRelease = BEAT_FRAMES - beatPosition;
        if (bassRelease < FADE_FRAMES) {
            bassEnvelope = bassRelease;
        }
        int32_t sample = triangle(bassPhase_) * 900 / 32768 *
                         static_cast<int32_t>(bassEnvelope) /
                         static_cast<int32_t>(FADE_FRAMES);
        bassPhase_ += bassIncrement_;

        const uint32_t phrasePosition = musicFrame_ % (BEAT_FRAMES * 8);
        uint32_t padEnvelope = phrasePosition < PAD_FADE_FRAMES
                                   ? phrasePosition
                                   : PAD_FADE_FRAMES;
        const uint32_t padRelease = BEAT_FRAMES * 8 - phrasePosition;
        if (padRelease < padEnvelope) {
            padEnvelope = padRelease;
        }
        for (size_t voice = 0; voice < 3; ++voice) {
            sample += triangle(padPhase_[voice]) * 250 / 32768 *
                      static_cast<int32_t>(padEnvelope) /
                      static_cast<int32_t>(PAD_FADE_FRAMES);
            padPhase_[voice] += padIncrement_[voice];
        }

        const uint32_t arpPosition = musicFrame_ % ARP_FRAMES;
        const uint32_t arpLength = ARP_FRAMES * 9 / 10;
        if (arpPosition < arpLength) {
            uint32_t envelope = arpPosition < FADE_FRAMES ? arpPosition : FADE_FRAMES;
            const uint32_t remaining = arpLength - 1 - arpPosition;
            if (remaining < envelope) {
                envelope = remaining;
            }
            sample += triangle(arpPhase_) * 350 / 32768 *
                      static_cast<int32_t>(envelope) /
                      static_cast<int32_t>(FADE_FRAMES);
            arpPhase_ += arpIncrement_;
        }

        const uint32_t leadLength = STEP_FRAMES * 9 / 10;
        if (leadIncrement_ != 0 && stepPosition < leadLength) {
            uint32_t envelope = stepPosition < FADE_FRAMES ? stepPosition : FADE_FRAMES;
            const uint32_t remaining = leadLength - 1 - stepPosition;
            if (remaining < envelope) {
                envelope = remaining;
            }
            sample += triangle(leadPhase_) * 1100 / 32768 *
                      static_cast<int32_t>(envelope) / static_cast<int32_t>(FADE_FRAMES);
            leadPhase_ += leadIncrement_;
        }
        ++musicFrame_;
        if (musicFrame_ == BEAT_FRAMES * MUSIC_BEATS) {
            musicFrame_ = 0;
        }
        return sample;
    }

    int32_t effectSample() {
        if (effect_ == Effect::Landing) {
            const uint32_t noteFrame = effectFrame_ % LAND_NOTE_FRAMES;
            if (noteFrame == 0) {
                effectPhase_ = 0;
                effectIncrement_ = increment(effectFrame_ == 0 ? 660 : 880);
            }
            uint32_t envelope = noteFrame < FADE_FRAMES ? noteFrame : FADE_FRAMES;
            const uint32_t remaining = LAND_NOTE_FRAMES - 1 - noteFrame;
            if (remaining < envelope) {
                envelope = remaining;
            }
            const int32_t sample = triangle(effectPhase_) * 4000 / 32768 *
                                   static_cast<int32_t>(envelope) /
                                   static_cast<int32_t>(FADE_FRAMES);
            effectPhase_ += effectIncrement_;
            if (++effectFrame_ == 2 * LAND_NOTE_FRAMES) {
                effect_ = Effect::None;
            }
            return sample;
        }
        if (effect_ == Effect::Crash) {
            crashFilter_ += (noise() - crashFilter_) / 4;
            int32_t sample = crashFilter_ * 6500 / 32768;
            sample = sample * static_cast<int32_t>(CRASH_FRAMES - effectFrame_) /
                     static_cast<int32_t>(CRASH_FRAMES);
            const uint32_t attack = effectFrame_ < FADE_FRAMES ? effectFrame_ : FADE_FRAMES;
            sample = sample * static_cast<int32_t>(attack) / static_cast<int32_t>(FADE_FRAMES);
            if (++effectFrame_ == CRASH_FRAMES) {
                effect_ = Effect::None;
            }
            return sample;
        }
        return 0;
    }

    GameAudioMode mode_ = GameAudioMode::Idle;
    bool thrust_ = false;
    Effect effect_ = Effect::None;
    uint32_t musicGain_ = 0, musicTarget_ = 0, engineEnvelope_ = 0;
    uint8_t musicVolume_ = 7, effectsVolume_ = 7;
    uint32_t musicFrame_ = 0, bassPhase_ = 0, leadPhase_ = 0;
    uint32_t bassIncrement_ = 0, leadIncrement_ = 0;
    uint32_t arpPhase_ = 0, arpIncrement_ = 0;
    uint32_t padPhase_[3] = {0, 0, 0};
    uint32_t padIncrement_[3] = {0, 0, 0};
    uint32_t effectFrame_ = 0, effectPhase_ = 0, effectIncrement_ = 0;
    uint32_t random_ = 0x6d2b79f5u;
    int32_t engineFilter_ = 0, crashFilter_ = 0;
};

class GameAudioDemo {
public:
    void start() {
        frame_ = 0;
        active_ = true;
    }

    bool next(GameAudioState& state, uint32_t frames) {
        if (!active_) {
            return false;
        }
        if (frame_ < ATTRACT_END) {
            state = {GameAudioMode::Attract, false};
        } else if (frame_ < FLY_END) {
            state = {GameAudioMode::Flying, false};
        } else if (frame_ < THRUST_END) {
            state = {GameAudioMode::Flying, true};
        } else if (frame_ < LAND_END) {
            state = {GameAudioMode::Landed, false};
        } else if (frame_ < RESUME_END) {
            state = {GameAudioMode::Flying, false};
        } else if (frame_ < CRASH_END) {
            state = {GameAudioMode::Crashed, false};
        } else {
            state = {GameAudioMode::Idle, false};
        }
        const uint32_t remaining = TOTAL_FRAMES - frame_;
        frame_ += frames < remaining ? frames : remaining;
        if (frame_ == TOTAL_FRAMES) {
            active_ = false;
        }
        return true;
    }

private:
    static constexpr uint32_t ATTRACT_END = GameAudio::SAMPLE_RATE * 2;
    static constexpr uint32_t FLY_END = GameAudio::SAMPLE_RATE * 3;
    static constexpr uint32_t THRUST_END = GameAudio::SAMPLE_RATE * 9 / 2;
    static constexpr uint32_t LAND_END = GameAudio::SAMPLE_RATE * 5;
    static constexpr uint32_t RESUME_END = GameAudio::SAMPLE_RATE * 21 / 4;
    static constexpr uint32_t CRASH_END = GameAudio::SAMPLE_RATE * 6;
    static constexpr uint32_t TOTAL_FRAMES = GameAudio::SAMPLE_RATE * 31 / 5;
    uint32_t frame_ = 0;
    bool active_ = false;
};

#endif
