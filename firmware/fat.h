#ifndef FAT_H
#define FAT_H

#include <stdint.h>

enum { FAT_OK, FAT_IO, FAT_FORMAT, FAT_NOT_FOUND, FAT_CHAIN, FAT_RANGE };
typedef int (*sector_reader)(void *context, uint32_t lba, uint8_t sector[512]);
typedef int (*sector_writer)(void *context, uint32_t lba, const uint8_t sector[512]);

struct fat_volume {
    sector_reader read;
    void *context;
    uint32_t start, total, fat, fat_start, fat_sectors, data, clusters;
    uint32_t root, root_sectors, root_cluster;
    uint8_t sectors_per_cluster, fat32, fat_count, fat_active, fat_mirror;
    uint8_t sector[512];
};

struct fat_file {
    struct fat_volume *volume;
    uint32_t cluster, size;
    char name[13];
};

uint16_t little16(const uint8_t *p);
uint32_t little32(const uint8_t *p);
int fat_mount(struct fat_volume *v, sector_reader read, void *context);
int fat_first_game(struct fat_volume *v, struct fat_file *file);
int fat_game_named(struct fat_volume *v, struct fat_file *file, const char name[11]);
int fat_game_count(struct fat_volume *v, uint32_t *count);
int fat_game_at(struct fat_volume *v, uint32_t index, struct fat_file *file);
int fat_settings_read(struct fat_volume *v, uint8_t *music, uint8_t *effects);
int fat_settings_write(struct fat_volume *v, sector_writer write,
                       uint8_t music, uint8_t effects);
int fat_file_sectors(const struct fat_file *file, uint32_t *sectors, unsigned count);
int fat_read_file(const struct fat_file *file, uint32_t offset,
                  uint8_t *destination, uint32_t length);

#endif
