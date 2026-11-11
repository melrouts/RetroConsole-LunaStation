#ifndef STARTUP_CHIME_H
#define STARTUP_CHIME_H

#include <math.h>
#include <stddef.h>
#include <stdint.h>

class StartupChime {
public:
    static constexpr uint32_t SAMPLE_RATE = 16000;
    static constexpr int16_t PEAK = 7500;
    static constexpr uint32_t NOTE_FRAMES = SAMPLE_RATE * 160 / 1000;
    static constexpr uint32_t PAUSE_FRAMES = SAMPLE_RATE * 40 / 1000;
    static constexpr uint32_t FADE_FRAMES = SAMPLE_RATE * 8 / 1000;
    static constexpr uint32_t TOTAL_FRAMES = 3 * (NOTE_FRAMES + PAUSE_FRAMES);

    void play() {
        position_ = 0;
    }

    bool playing() const {
        return position_ < TOTAL_FRAMES;
    }

    void render(int16_t* stereo, size_t frames) {
        static constexpr float frequencies[] = {523.25f, 659.25f, 783.99f};
        for (size_t i = 0; i < frames; ++i) {
            int16_t sample = 0;
            if (playing()) {
                const uint32_t note = position_ / (NOTE_FRAMES + PAUSE_FRAMES);
                const uint32_t frame = position_ % (NOTE_FRAMES + PAUSE_FRAMES);
                if (frame < NOTE_FRAMES) {
                    uint32_t envelope = FADE_FRAMES;
                    if (frame < envelope) {
                        envelope = frame;
                    }
                    const uint32_t remaining = NOTE_FRAMES - 1 - frame;
                    if (remaining < envelope) {
                        envelope = remaining;
                    }
                    const float phase = 6.28318530718f * frequencies[note] *
                                        frame / SAMPLE_RATE;
                    sample = static_cast<int16_t>(
                        sinf(phase) * PEAK * envelope / FADE_FRAMES);
                }
                ++position_;
            }
            // MAX98357A mixes L+R by default; send the same signal to both slots.
            stereo[2 * i] = sample;
            stereo[2 * i + 1] = sample;
        }
    }

private:
    uint32_t position_ = TOTAL_FRAMES;
};

#endif
