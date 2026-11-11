#ifndef BUTTON_MAPPING_H
#define BUTTON_MAPPING_H

#include <stdint.h>

constexpr uint8_t remapControllerButtons(uint8_t buttons) {
    return static_cast<uint8_t>((buttons & 0x09u) |
                                ((buttons & 0x02u) << 1) |
                                ((buttons & 0x04u) >> 1));
}

#endif
