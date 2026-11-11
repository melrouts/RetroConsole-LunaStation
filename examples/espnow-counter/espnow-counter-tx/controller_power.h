#pragma once

#include <stdint.h>

namespace ControllerPower {

constexpr uint8_t MENU = 0x08;
constexpr uint32_t DEBOUNCE_MS = 20;
constexpr uint32_t MENU_HOLD_MS = 2000;
constexpr uint32_t MENU_PULSE_MS = 100;
constexpr uint32_t FRAME_MS = 140;
constexpr uint32_t TRANSITION_MS = 4 * FRAME_MS;

class Buttons {
public:
    uint8_t update(uint8_t raw, uint32_t now) {
        for (uint8_t i = 0; i < 4; ++i) {
            const uint8_t bit = 1u << i;
            if ((raw ^ raw_) & bit) {
                changedAt_[i] = now;
            } else if (((raw ^ held_) & bit) &&
                       now - changedAt_[i] >= DEBOUNCE_MS) {
                held_ ^= bit;
            }
        }
        raw_ = raw;
        return held_;
    }

private:
    uint8_t raw_ = 0;
    uint8_t held_ = 0;
    uint32_t changedAt_[4]{};
};

enum class Mode : uint8_t { Active, Entering, WaitRelease, Waking, WaitWakeRelease };

class State {
public:
    uint8_t update(uint8_t held, uint32_t now) {
        if (mode_ == Mode::Entering || mode_ == Mode::Waking) {
            if (now - transitionAt_ >= TRANSITION_MS) {
                mode_ = mode_ == Mode::Entering ? Mode::WaitRelease
                                               : Mode::WaitWakeRelease;
            }
            return 0;
        }
        if (mode_ != Mode::Active) {
            return 0;
        }
        if (menuPulse_ && now - pulseAt_ >= MENU_PULSE_MS) {
            menuPulse_ = false;
        }
        if (held & MENU) {
            if (!menuHeld_) {
                menuHeld_ = true;
                menuAt_ = now;
                menuPulse_ = false;
            }
            if (now - menuAt_ >= MENU_HOLD_MS) {
                mode_ = Mode::Entering;
                transitionAt_ = now;
                menuHeld_ = false;
                menuPulse_ = false;
                return 0;
            }
        } else if (menuHeld_) {
            menuHeld_ = false;
            menuPulse_ = true;
            pulseAt_ = now;
        }
        return (held & ~MENU) | (menuPulse_ ? MENU : 0);
    }

    // Require both raw and debounced release: a new press must not slip through
    // the debounce window while arming sleep or restoring gameplay.
    void released(uint8_t raw, uint8_t held) {
        if (mode_ == Mode::WaitWakeRelease && raw == 0 && held == 0) {
            mode_ = Mode::Active;
        }
    }

    bool shouldSleep(uint8_t raw, uint8_t held) const {
        return mode_ == Mode::WaitRelease && raw == 0 && held == 0;
    }

    void wake(uint32_t now) {
        mode_ = Mode::Waking;
        transitionAt_ = now;
    }

    Mode mode() const { return mode_; }
    uint8_t frame(uint32_t now) const {
        const uint32_t frame = (now - transitionAt_) / FRAME_MS;
        return frame < 4 ? static_cast<uint8_t>(frame) : 3;
    }

private:
    Mode mode_ = Mode::Active;
    bool menuHeld_ = false;
    bool menuPulse_ = false;
    uint32_t menuAt_ = 0;
    uint32_t pulseAt_ = 0;
    uint32_t transitionAt_ = 0;
};

}  // namespace ControllerPower
