#include "image.h"
#include "fat.h"

uint32_t image_crc(uint32_t state, const uint8_t *data, uint32_t size)
{
    while (size--) {
        state ^= *data++;
        for (unsigned bit = 0; bit < 8; ++bit)
            state = (state >> 1) ^ ((state & 1) ? 0xedb88320u : 0);
    }
    return state;
}

int image_header(const uint8_t header[32], uint32_t file_size, uint32_t ram_bytes,
                 uint32_t stack_bytes, uint16_t abi, struct game_image *image)
{
    if (header[0] != 'L' || header[1] != 'U' || header[2] != 'N' || header[3] != 'A' ||
        little16(header + 4) != 1 || little32(header + 20) ||
        (image_crc(UINT32_MAX, header, 28) ^ UINT32_MAX) != little32(header + 28))
        return 4;
    if (little16(header + 6) != abi)
        return 6;
    image->size = little32(header + 8);
    image->load = little32(header + 12);
    image->entry = little32(header + 16);
    image->payload_crc = little32(header + 24);
    if (!stack_bytes || stack_bytes >= ram_bytes || file_size < 32 ||
        image->size != file_size - 32 || !image->size ||
        (image->load & 3) || (image->entry & 3) ||
        image->load >= ram_bytes - stack_bytes ||
        image->size > ram_bytes - stack_bytes - image->load ||
        image->size < 4 || image->entry < image->load ||
        image->entry - image->load > image->size - 4)
        return 4;
    return 0;
}
