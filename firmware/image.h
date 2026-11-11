#ifndef IMAGE_H
#define IMAGE_H

#include <stdint.h>

struct game_image {
    uint32_t size, load, entry, payload_crc;
};

uint32_t image_crc(uint32_t state, const uint8_t *data, uint32_t size);
int image_header(const uint8_t header[32], uint32_t file_size, uint32_t ram_bytes,
                 uint32_t stack_bytes, uint16_t abi, struct game_image *image);

#endif
