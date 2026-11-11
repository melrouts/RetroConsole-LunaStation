#ifndef UPDATE_H
#define UPDATE_H
#include "fat.h"
#include "image.h"

#define UPDATE_SECTORS 16
#define UPDATE_BYTES (UPDATE_SECTORS * 512u)
#define UPDATE_MAX_IMAGE 7200u
typedef int (*sector_writer)(void *, uint32_t, const uint8_t *);
struct update_slot {
    uint32_t sectors[UPDATE_SECTORS];
    uint32_t generation, size;
};
int update_prepare(struct fat_volume *v, struct update_slot slots[2]);
int update_validate(struct fat_volume *v, struct update_slot *slot);
int update_commit(struct fat_volume *v, sector_writer write, struct update_slot *slot,
                  const uint8_t *image, uint32_t size, uint32_t generation);
int update_read(struct fat_volume *v, const struct update_slot *slot,
                uint32_t offset, uint8_t *data, uint32_t size);
#endif
