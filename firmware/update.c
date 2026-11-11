#include "update.h"

static void put32(uint8_t *p, uint32_t value)
{
    for (unsigned i = 0; i < 4; ++i)
        p[i] = (uint8_t)(value >> (i * 8));
}

int update_prepare(struct fat_volume *v, struct update_slot slots[2])
{
    struct fat_file file;
    for (unsigned slot = 0; slot < 2; ++slot) {
        slots[slot].generation = 0;
        if (fat_game_named(v, &file, slot ? "UPDATEB BIN" : "UPDATEA BIN") ||
            file.size != UPDATE_BYTES ||
            fat_file_sectors(&file, slots[slot].sectors, UPDATE_SECTORS))
            return -1;
    }
    for (unsigned a = 0; a < UPDATE_SECTORS; ++a)
        for (unsigned b = 0; b < UPDATE_SECTORS; ++b)
            if (slots[0].sectors[a] == slots[1].sectors[b])
                return -1;
    /* Refuse slots sharing data sectors with the factory image. */
    int found = fat_game_named(v, &file, "LUNAR   BIN");
    if (found != FAT_NOT_FOUND) {
        uint32_t sectors[UPDATE_SECTORS];
        unsigned count = (file.size + 511u) / 512u;
        if (found || !count || count > UPDATE_SECTORS ||
            fat_file_sectors(&file, sectors, count))
            return -1;
        for (unsigned i = 0; i < count; ++i)
            for (unsigned j = 0; j < UPDATE_SECTORS; ++j)
                if (sectors[i] == slots[0].sectors[j] || sectors[i] == slots[1].sectors[j])
                    return -1;
    }
    return 0;
}

int update_read(struct fat_volume *v, const struct update_slot *slot,
                uint32_t offset, uint8_t *data, uint32_t size)
{
    if (slot->size > UPDATE_MAX_IMAGE || offset > slot->size || size > slot->size - offset)
        return -1;
    while (size) {
        uint32_t count = 512u - offset % 512u;
        if (count > size)
            count = size;
        if (v->read(v->context, slot->sectors[1 + offset / 512u], v->sector))
            return -1;
        for (unsigned i = 0; i < count; ++i)
            *data++ = v->sector[offset % 512u + i];
        offset += count;
        size -= count;
    }
    return 0;
}

int update_validate(struct fat_volume *v, struct update_slot *slot)
{
    slot->generation = 0;
    if (v->read(v->context, slot->sectors[0], v->sector))
        return -1;
    const uint8_t *header = v->sector;
    if (little32(header) != 0x31445055u ||
        (image_crc(UINT32_MAX, header, 28) ^ UINT32_MAX) != little32(header + 28))
        return 1;
    uint32_t generation = little32(header + 4), size = little32(header + 8);
    uint32_t expected = little32(header + 12);
    if (!generation || size < 36 || size > UPDATE_MAX_IMAGE)
        return 1;
    for (unsigned i = 16; i < 28; ++i)
        if (header[i])
            return 1;
    slot->size = size;
    uint8_t luna[32];
    struct game_image parsed;
    if (update_read(v, slot, 0, luna, sizeof luna))
        return -1;
    if (image_header(luna, size, 8192, 1024, 1, &parsed))
        return 1;
    uint32_t crc = UINT32_MAX, payload_crc = UINT32_MAX;
    for (uint32_t offset = 0; offset < size;) {
        unsigned count = size - offset > 512 ? 512 : size - offset;
        if (v->read(v->context, slot->sectors[1 + offset / 512u], v->sector))
            return -1;
        crc = image_crc(crc, v->sector, count);
        unsigned skip = offset ? 0 : 32;
        payload_crc = image_crc(payload_crc, v->sector + skip, count - skip);
        offset += count;
    }
    if ((crc ^ UINT32_MAX) != expected || (payload_crc ^ UINT32_MAX) != parsed.payload_crc)
        return 1;
    slot->generation = generation;
    return 0;
}

int update_commit(struct fat_volume *v, sector_writer write, struct update_slot *slot,
                  const uint8_t *image, uint32_t size, uint32_t generation)
{
    struct game_image parsed;
    if (!generation || size < 36 || size > UPDATE_MAX_IMAGE ||
        image_header(image, size, 8192, 1024, 1, &parsed) ||
        (image_crc(UINT32_MAX, image + 32, size - 32) ^ UINT32_MAX) != parsed.payload_crc)
        return -1;
    /* Invalidate the inactive slot before touching its data; commit metadata last. */
    for (unsigned i = 0; i < 512; ++i)
        v->sector[i] = 0;
    if (write(v->context, slot->sectors[0], v->sector))
        return -1;
    for (uint32_t offset = 0; offset < size; offset += 512) {
        unsigned count = size - offset > 512 ? 512 : size - offset;
        for (unsigned i = 0; i < 512; ++i)
            v->sector[i] = i < count ? image[offset + i] : 0;
        uint32_t lba = slot->sectors[1 + offset / 512u];
        if (write(v->context, lba, v->sector) || v->read(v->context, lba, v->sector))
            return -1;
        for (unsigned i = 0; i < 512; ++i)
            if (v->sector[i] != (i < count ? image[offset + i] : 0))
                return -1;
    }
    for (unsigned i = 0; i < 512; ++i)
        v->sector[i] = 0;
    put32(v->sector, 0x31445055u);
    put32(v->sector + 4, generation);
    put32(v->sector + 8, size);
    put32(v->sector + 12, image_crc(UINT32_MAX, image, size) ^ UINT32_MAX);
    put32(v->sector + 28, image_crc(UINT32_MAX, v->sector, 28) ^ UINT32_MAX);
    if (write(v->context, slot->sectors[0], v->sector) || update_validate(v, slot) ||
        slot->generation != generation)
        return -1;
    return 0;
}
