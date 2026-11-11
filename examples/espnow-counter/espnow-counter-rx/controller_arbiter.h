#ifndef CONTROLLER_ARBITER_H
#define CONTROLLER_ARBITER_H

#include <stddef.h>
#include <stdint.h>
#include <string.h>

// Chooses which wireless controller drives the console.
// Outside a game session (menus, memorials, demo) every controller is merged;
// the most recent controller to press THRUST becomes the player, so the press
// that starts a game also claims it. During a session only the player's buttons
// are used. Returning from a session to the lobby releases the player.
class ControllerArbiter {
public:
    static constexpr size_t MAX_CONTROLLERS = 4;
    static constexpr uint32_t HOLD_TIMEOUT_MS = 250;
    static constexpr uint8_t THRUST = 0x02;  // bit in the remapped Tang mask
    static constexpr int NONE = -1;

    // Returns the controller slot, or NONE if the table is full of active controllers.
    // `relevant` reports whether the packet affects the forwarded mask.
    int packet(const uint8_t mac[6], uint8_t buttons, uint32_t now, bool& relevant) {
        relevant = false;
        const int slot = slotFor(mac, now);
        if (slot == NONE) {
            return NONE;
        }
        Controller& controller = controllers_[slot];
        const bool hadThrust = fresh(controller, now) && (controller.buttons & THRUST) != 0;
        controller.buttons = buttons;
        controller.lastPacketMs = now;
        controller.seen = true;
        if ((buttons & THRUST) != 0 && !hadThrust && (!session_ || owner_ == NONE)) {
            owner_ = slot;
        }
        relevant = !session_ || owner_ == NONE || owner_ == slot;
        return slot;
    }

    // Returns true if this call released the player.
    bool setSession(bool session) {
        const bool released = session_ && !session && owner_ != NONE;
        if (released) {
            owner_ = NONE;
        }
        session_ = session;
        return released;
    }

    uint8_t output(uint32_t now) const {
        if (session_ && owner_ != NONE) {
            return fresh(controllers_[owner_], now) ? controllers_[owner_].buttons : 0;
        }
        uint8_t mask = 0;
        for (const Controller& controller : controllers_) {
            if (fresh(controller, now)) {
                mask |= controller.buttons;
            }
        }
        return mask;
    }

    int owner() const { return owner_; }
    bool session() const { return session_; }

    const uint8_t* mac(int slot) const {
        return slot >= 0 && static_cast<size_t>(slot) < MAX_CONTROLLERS &&
                       controllers_[slot].seen
                   ? controllers_[slot].mac
                   : nullptr;
    }

private:
    struct Controller {
        uint8_t mac[6];
        uint8_t buttons;
        uint32_t lastPacketMs;
        bool seen;
    };

    static bool fresh(const Controller& controller, uint32_t now) {
        return controller.seen && controller.buttons != 0 &&
               static_cast<uint32_t>(now - controller.lastPacketMs) < HOLD_TIMEOUT_MS;
    }

    int slotFor(const uint8_t mac[6], uint32_t now) {
        int freeSlot = NONE;
        int oldest = NONE;
        for (size_t i = 0; i < MAX_CONTROLLERS; ++i) {
            const Controller& controller = controllers_[i];
            if (controller.seen && memcmp(controller.mac, mac, 6) == 0) {
                return static_cast<int>(i);
            }
            if (!controller.seen) {
                if (freeSlot == NONE) {
                    freeSlot = static_cast<int>(i);
                }
            } else if (static_cast<int>(i) != owner_ && !fresh(controller, now) &&
                       (oldest == NONE ||
                        static_cast<int32_t>(controller.lastPacketMs -
                                             controllers_[oldest].lastPacketMs) < 0)) {
                oldest = static_cast<int>(i);
            }
        }
        const int slot = freeSlot != NONE ? freeSlot : oldest;
        if (slot != NONE) {
            Controller& controller = controllers_[slot];
            memcpy(controller.mac, mac, 6);
            controller.buttons = 0;
            controller.lastPacketMs = now;
            controller.seen = true;
        }
        return slot;
    }

    Controller controllers_[MAX_CONTROLLERS]{};
    int owner_ = NONE;
    bool session_ = false;
};

#endif
