#ifndef GAME_AUDIO_LINK_H
#define GAME_AUDIO_LINK_H

#include <stdint.h>

enum class GameAudioMode : uint8_t {
    Idle,       // no music, no effects
    Flying,     // in-game flight: music at the in-game level
    Landed,     // landing effect; music continues at its current level
    Crashed,    // crash effect; music continues at its current level
    Attract,    // main screen and memorials: music at the menu level
    DemoFlying, // autopilot flight: music at the menu level
};

struct GameAudioState {
    GameAudioMode mode;
    bool thrust;
};

// The console sends a 3-bit scene as 01sss sss. All eight scenes are valid:
//   0 idle   1 flying   2 landed   3 crashed   4 attract
//   5 flying + thrust   6 demo flying   7 demo flying + thrust
class GameAudioLink {
public:
    static constexpr uint32_t TIMEOUT_MS = 500;

    static bool isFrame(uint8_t value) {
        return (value & 0xc0u) == 0x40u;
    }

    static bool isSettingsFrame(uint8_t value) {
        return (value & 0xc0u) == 0xc0u;
    }

    static uint8_t musicVolume(uint8_t value) {
        return static_cast<uint8_t>((value >> 3) & 7u);
    }

    static uint8_t effectsVolume(uint8_t value) {
        return static_cast<uint8_t>(value & 7u);
    }

    static GameAudioState decode(uint8_t scene) {
        switch (scene & 7u) {
        case 1: return {GameAudioMode::Flying, false};
        case 2: return {GameAudioMode::Landed, false};
        case 3: return {GameAudioMode::Crashed, false};
        case 4: return {GameAudioMode::Attract, false};
        case 5: return {GameAudioMode::Flying, true};
        case 6: return {GameAudioMode::DemoFlying, false};
        case 7: return {GameAudioMode::DemoFlying, true};
        default: return {GameAudioMode::Idle, false};
        }
    }

    static const char* modeName(GameAudioMode mode) {
        switch (mode) {
        case GameAudioMode::Flying: return "flying";
        case GameAudioMode::Landed: return "landed";
        case GameAudioMode::Crashed: return "crashed";
        case GameAudioMode::Attract: return "attract";
        case GameAudioMode::DemoFlying: return "demo";
        default: return "idle";
        }
    }

    bool accept(uint8_t value, uint32_t now) {
        if (!isFrame(value)) {
            return false;
        }
        // The two copies detect any single-bit error in the scene.
        if (((value >> 3) & 7u) != (value & 7u)) {
            return false;
        }
        state_ = decode(value);
        receivedAt_ = now;
        received_ = true;
        return true;
    }

    GameAudioState state(uint32_t now) const {
        if (!received_ || static_cast<uint32_t>(now - receivedAt_) > TIMEOUT_MS) {
            return {GameAudioMode::Idle, false};
        }
        return state_;
    }

private:
    GameAudioState state_{GameAudioMode::Idle, false};
    uint32_t receivedAt_ = 0;
    bool received_ = false;
};

#endif
