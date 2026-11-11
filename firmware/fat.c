#include "fat.h"

uint16_t little16(const uint8_t *p)
{
    return (uint16_t)((uint16_t)p[0] | (uint16_t)p[1] << 8);
}

uint32_t little32(const uint8_t *p)
{
    return (uint32_t)p[0] | (uint32_t)p[1] << 8 |
           (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
}

static int read_relative(struct fat_volume *v, uint32_t sector)
{
    if (sector >= v->total)
        return FAT_RANGE;
    return v->read(v->context, v->start + sector, v->sector) ? FAT_IO : FAT_OK;
}

static int valid_cluster(const struct fat_volume *v, uint32_t cluster)
{
    return cluster >= 2 && cluster - 2 < v->clusters;
}

static int next_cluster(struct fat_volume *v, uint32_t cluster, uint32_t *next)
{
    if (!valid_cluster(v, cluster))
        return FAT_CHAIN;
    uint32_t entry_size = v->fat32 ? 4u : 2u;
    uint32_t offset = cluster * entry_size;
    int status = read_relative(v, v->fat + offset / 512);
    if (status)
        return status;
    const uint8_t *p = v->sector + offset % 512;
    *next = v->fat32 ? little32(p) & 0x0fffffffu : little16(p);
    if (*next >= (v->fat32 ? 0x0ffffff8u : 0xfff8u)) {
        *next = 0;
        return FAT_OK;
    }
    return valid_cluster(v, *next) ? FAT_OK : FAT_CHAIN;
}

int fat_mount(struct fat_volume *v, sector_reader read, void *context)
{
    v->read = read;
    v->context = context;
    if (read(context, 0, v->sector))
        return FAT_IO;
    if (little16(v->sector + 510) != 0xaa55)
        return FAT_FORMAT;
    uint32_t partition_size = 0;
    v->start = 0;
    for (unsigned index = 0; index < 4; ++index) {
        const uint8_t *entry = v->sector + 446 + index * 16;
        uint8_t type = entry[4];
        if (type == 4 || type == 6 || type == 0x0e || type == 0x0b || type == 0x0c) {
            v->start = little32(entry + 8);
            partition_size = little32(entry + 12);
            break;
        }
    }
    if (!v->start || !partition_size || v->start > UINT32_MAX - partition_size)
        return FAT_FORMAT;
    if (read(context, v->start, v->sector))
        return FAT_IO;
    const uint8_t *b = v->sector;
    if (little16(b + 510) != 0xaa55 || little16(b + 11) != 512)
        return FAT_FORMAT;
    v->sectors_per_cluster = b[13];
    if (!b[13] || b[13] > 128 || (b[13] & (b[13] - 1)))
        return FAT_FORMAT;
    uint32_t reserved = little16(b + 14);
    uint32_t fats = b[16];
    uint32_t root_entries = little16(b + 17);
    v->root_sectors = (root_entries * 32u + 511u) / 512u;
    v->total = little16(b + 19);
    if (!v->total)
        v->total = little32(b + 32);
    uint32_t fat16_size = little16(b + 22);
    v->fat_sectors = fat16_size ? fat16_size : little32(b + 36);
    if (!reserved || !fats || fats > 2 || !v->fat_sectors ||
        v->total > partition_size || reserved >= v->total ||
        v->root_sectors >= v->total - reserved ||
        v->fat_sectors > (v->total - reserved - v->root_sectors) / fats)
        return FAT_FORMAT;
    v->fat_start = reserved;
    v->fat = reserved;
    v->fat_count = (uint8_t)fats;
    v->fat_active = 0;
    v->fat_mirror = 1;
    v->root = reserved + fats * v->fat_sectors;
    v->data = v->root + v->root_sectors;
    v->clusters = (v->total - v->data) / v->sectors_per_cluster;
    if (v->clusters < 4085 || v->clusters >= 0x0ffffff5u)
        return FAT_FORMAT;
    v->fat32 = v->clusters >= 65525;
    if (v->fat32) {
        if (fat16_size || root_entries || little16(b + 42))
            return FAT_FORMAT;
        uint16_t flags = little16(b + 40);
        if (flags & 0x80) {
            unsigned active_fat = flags & 0x0f;
            if (active_fat >= fats)
                return FAT_FORMAT;
            v->fat_active = (uint8_t)active_fat;
            v->fat_mirror = 0;
            v->fat += active_fat * v->fat_sectors;
        }
        v->root_cluster = little32(b + 44) & 0x0fffffffu;
        if (!valid_cluster(v, v->root_cluster))
            return FAT_FORMAT;
    } else {
        if (!fat16_size || !root_entries)
            return FAT_FORMAT;
        v->root_cluster = 0;
    }
    uint32_t entries_per_sector = v->fat32 ? 128u : 256u;
    if (v->fat_sectors < (v->clusters + 2 + entries_per_sector - 1) / entries_per_sector)
        return FAT_FORMAT;
    return FAT_OK;
}

static uint8_t upper(uint8_t c)
{
    return c >= 'a' && c <= 'z' ? (uint8_t)(c - 'a' + 'A') : c;
}

static uint32_t entry_cluster(const struct fat_volume *v, const uint8_t *entry)
{
    return little16(entry + 26) |
           (v->fat32 ? (uint32_t)little16(entry + 20) << 16 : 0);
}

static int scan_directory(struct fat_volume *v, uint32_t cluster, int games,
                          struct fat_file *file, const char *wanted,
                          uint32_t wanted_index, uint32_t *matches)
{
    uint32_t sectors_scanned = 0;
    uint32_t clusters_scanned = 0;
    uint32_t game_index = 0;
    int fixed_root = !cluster && !v->fat32;
    do {
        if (!fixed_root && !valid_cluster(v, cluster))
            return FAT_CHAIN;
        uint32_t first = fixed_root ? v->root :
                         v->data + (cluster - 2) * v->sectors_per_cluster;
        uint32_t count = fixed_root ? v->root_sectors : v->sectors_per_cluster;
        for (uint32_t s = 0; s < count; ++s) {
            if (++sectors_scanned > 256)
                return FAT_RANGE;
            int status = read_relative(v, first + s);
            if (status)
                return status;
            for (unsigned i = 0; i < 512; i += 32) {
                const uint8_t *entry = v->sector + i;
                if (!entry[0]) {
                    if (matches)
                        *matches = game_index;
                    return FAT_NOT_FOUND;
                }
                if (entry[0] == 0xe5 || entry[0] == '.' || (entry[11] & 0x0e))
                    continue;
                if (!games) {
                    static const char name[] = "GAMES      ";
                    unsigned match = 0;
                    while (match < 11 && upper(entry[match]) == (uint8_t)name[match])
                        ++match;
                    if (match != 11 || !(entry[11] & 0x10))
                        continue;
                } else if ((entry[11] & 0x10) ||
                           (!wanted && (upper(entry[8]) != 'B' ||
                                        upper(entry[9]) != 'I' ||
                                        upper(entry[10]) != 'N'))) {
                    continue;
                }
                if (games && wanted) {
                    unsigned match = 0;
                    while (match < 11 && upper(entry[match]) == (uint8_t)wanted[match])
                        ++match;
                    if (match != 11)
                        continue;
                }
                if (games && !wanted && upper(entry[0]) == 'U' && upper(entry[1]) == 'P' &&
                    upper(entry[2]) == 'D' && upper(entry[3]) == 'A' && upper(entry[4]) == 'T' &&
                    upper(entry[5]) == 'E' && (upper(entry[6]) == 'A' || upper(entry[6]) == 'B') &&
                    entry[7] == ' ')
                    continue;
                if (games && !wanted) {
                    if (game_index++ != wanted_index)
                        continue;
                }
                file->volume = v;
                file->cluster = entry_cluster(v, entry);
                file->size = little32(entry + 28);
                unsigned length = 0;
                for (unsigned j = 0; j < 8 && entry[j] != ' '; ++j)
                    file->name[length++] = (char)entry[j];
                file->name[length++] = '.';
                for (unsigned j = 8; j < 11 && entry[j] != ' '; ++j)
                    file->name[length++] = (char)entry[j];
                file->name[length] = 0;
                if (matches)
                    *matches = game_index;
                return valid_cluster(v, file->cluster) ? FAT_OK : FAT_CHAIN;
            }
        }
        if (fixed_root)
            break;
        int status = next_cluster(v, cluster, &cluster);
        if (status)
            return status;
        if (++clusters_scanned > v->clusters)
            return FAT_CHAIN;
    } while (cluster);
    if (matches)
        *matches = game_index;
    return FAT_NOT_FOUND;
}

int fat_first_game(struct fat_volume *v, struct fat_file *file)
{
    int status = scan_directory(v, v->root_cluster, 0, file, 0, 0, 0);
    return status ? status : scan_directory(v, file->cluster, 1, file, 0, 0, 0);
}

int fat_game_named(struct fat_volume *v, struct fat_file *file, const char name[11])
{
    int status = scan_directory(v, v->root_cluster, 0, file, 0, 0, 0);
    return status ? status : scan_directory(v, file->cluster, 1, file, name, 0, 0);
}

static int games_cluster(struct fat_volume *v, uint32_t *cluster)
{
    struct fat_file games;
    int status = scan_directory(v, v->root_cluster, 0, &games, 0, 0, 0);
    if (!status)
        *cluster = games.cluster;
    return status;
}

int fat_game_count(struct fat_volume *v, uint32_t *count)
{
    uint32_t cluster;
    int status = games_cluster(v, &cluster);
    if (status)
        return status;
    struct fat_file ignored;
    *count = 0;
    status = scan_directory(v, cluster, 1, &ignored, 0, UINT32_MAX, count);
    return status == FAT_NOT_FOUND ? FAT_OK : status;
}

int fat_game_at(struct fat_volume *v, uint32_t index, struct fat_file *file)
{
    uint32_t cluster;
    int status = games_cluster(v, &cluster);
    return status ? status : scan_directory(v, cluster, 1, file, 0, index, 0);
}

int fat_read_file(const struct fat_file *file, uint32_t offset,
                  uint8_t *destination, uint32_t length)
{
    if (offset > file->size || length > file->size - offset)
        return FAT_RANGE;
    struct fat_volume *v = file->volume;
    uint32_t cluster = file->cluster;
    uint32_t cluster_bytes = (uint32_t)v->sectors_per_cluster * 512u;
    uint32_t skip = offset / cluster_bytes;
    if (skip >= v->clusters)
        return FAT_CHAIN;
    while (skip--) {
        int status = next_cluster(v, cluster, &cluster);
        if (status || !cluster)
            return status ? status : FAT_CHAIN;
    }

    offset %= cluster_bytes;
    while (length) {
        if (!valid_cluster(v, cluster))
            return FAT_CHAIN;
        uint32_t sector = v->data + (cluster - 2) * v->sectors_per_cluster + offset / 512u;
        int status = read_relative(v, sector);
        if (status)
            return status;
        uint32_t within = offset % 512u;
        uint32_t count = 512u - within;
        if (count > length)
            count = length;
        for (uint32_t i = 0; i < count; ++i)
            destination[i] = v->sector[within + i];
        destination += count;
        length -= count;
        offset += count;
        if (offset == cluster_bytes && length) {
            status = next_cluster(v, cluster, &cluster);
            if (status || !cluster)
                return status ? status : FAT_CHAIN;
            offset = 0;
        }
    }
    return FAT_OK;
}

static int directory_disjoint(struct fat_volume *v, uint32_t cluster,
                              const uint32_t *sectors, unsigned count)
{
    unsigned scanned = 0;
    while (cluster) {
        if (!valid_cluster(v, cluster) || (scanned += v->sectors_per_cluster) > 256)
            return FAT_CHAIN;
        uint32_t first = v->start + v->data + (cluster - 2) * v->sectors_per_cluster;
        for (unsigned i = 0; i < count; ++i)
            if (sectors[i] >= first && sectors[i] - first < v->sectors_per_cluster)
                return FAT_CHAIN;
        int status = next_cluster(v, cluster, &cluster);
        if (status)
            return status;
    }
    return FAT_OK;
}

int fat_file_sectors(const struct fat_file *file, uint32_t *sectors, unsigned count)
{
    if (!count || file->size / 512u + (file->size % 512u != 0) != count)
        return FAT_RANGE;
    struct fat_volume *v = file->volume;
    uint32_t cluster = file->cluster;
    for (unsigned i = 0; i < count; ++i) {
        if (!valid_cluster(v, cluster))
            return FAT_CHAIN;
        sectors[i] = v->start + v->data + (cluster - 2) * v->sectors_per_cluster +
                     i % v->sectors_per_cluster;
        for (unsigned j = 0; j < i; ++j)
            if (sectors[i] == sectors[j])
                return FAT_CHAIN;
        if ((i + 1) % v->sectors_per_cluster == 0 && i + 1 < count) {
            int status = next_cluster(v, cluster, &cluster);
            if (status || !cluster)
                return status ? status : FAT_CHAIN;
        }
    }
    struct fat_file games;
    int status = scan_directory(v, v->root_cluster, 0, &games, 0, 0, 0);
    if (!status)
        status = directory_disjoint(v, v->root_cluster, sectors, count);
    return status ? status : directory_disjoint(v, games.cluster, sectors, count);
}

static int directory_free_slot(struct fat_volume *v, uint32_t cluster,
                               uint32_t *sector, unsigned *offset)
{
    uint32_t sectors_scanned = 0, clusters_scanned = 0;
    while (cluster) {
        if (!valid_cluster(v, cluster))
            return FAT_CHAIN;
        uint32_t first = v->data + (cluster - 2) * v->sectors_per_cluster;
        for (unsigned s = 0; s < v->sectors_per_cluster; ++s) {
            if (++sectors_scanned > 256)
                return FAT_RANGE;
            int status = read_relative(v, first + s);
            if (status)
                return status;
            for (unsigned i = 0; i < 512; i += 32) {
                if (!v->sector[i] || v->sector[i] == 0xe5) {
                    *sector = v->start + first + s;
                    *offset = i;
                    return FAT_OK;
                }
            }
        }
        int status = next_cluster(v, cluster, &cluster);
        if (status)
            return status;
        if (++clusters_scanned > v->clusters)
            return FAT_CHAIN;
    }
    return FAT_NOT_FOUND;
}

static int fat_value(struct fat_volume *v, uint32_t cluster, uint32_t *value)
{
    uint32_t entry_size = v->fat32 ? 4u : 2u;
    uint32_t offset = cluster * entry_size;
    int status = read_relative(v, v->fat + offset / 512);
    if (status)
        return status;
    const uint8_t *entry = v->sector + offset % 512;
    *value = v->fat32 ? little32(entry) & 0x0fffffffu : little16(entry);
    return FAT_OK;
}

static int set_fat_value(struct fat_volume *v, sector_writer write,
                         uint32_t cluster, uint32_t value)
{
    uint32_t entry_size = v->fat32 ? 4u : 2u;
    uint32_t offset = cluster * entry_size;
    unsigned first = v->fat_mirror ? 0 : v->fat_active;
    unsigned end = v->fat_mirror ? v->fat_count : first + 1;
    for (unsigned copy = first; copy < end; ++copy) {
        uint32_t sector = v->fat_start + copy * v->fat_sectors + offset / 512;
        int status = read_relative(v, sector);
        if (status)
            return status;
        uint8_t *entry = v->sector + offset % 512;
        if (v->fat32) {
            uint32_t old = little32(entry);
            uint32_t updated = (old & 0xf0000000u) | (value & 0x0fffffffu);
            for (unsigned i = 0; i < 4; ++i)
                entry[i] = (uint8_t)(updated >> (i * 8));
        } else {
            entry[0] = (uint8_t)value;
            entry[1] = (uint8_t)(value >> 8);
        }
        if (write(v->context, v->start + sector, v->sector))
            return FAT_IO;
        status = read_relative(v, sector);
        if (status)
            return status;
        entry = v->sector + offset % 512;
        uint32_t verified = v->fat32 ? little32(entry) & 0x0fffffffu : little16(entry);
        if (verified != value)
            return FAT_IO;
    }
    return FAT_OK;
}

static int settings_entry(struct fat_volume *v, struct fat_file *file)
{
    uint32_t cluster;
    int status = games_cluster(v, &cluster);
    return status ? status : scan_directory(v, cluster, 1, file, "LUNASET CFG", 0, 0);
}

int fat_settings_read(struct fat_volume *v, uint8_t *music, uint8_t *effects)
{
    struct fat_file file;
    int status = settings_entry(v, &file);
    if (status)
        return status;
    uint8_t config[8];
    if (file.size != sizeof config || fat_read_file(&file, 0, config, sizeof config))
        return FAT_FORMAT;
    uint8_t check = 0xa5;
    for (unsigned i = 0; i < 7; ++i)
        check ^= config[i];
    if (config[0] != 'L' || config[1] != '9' || config[2] != 'C' ||
        config[3] != 'F' || config[6] != 1 || config[7] != check ||
        config[4] > 7 || config[5] > 7)
        return FAT_FORMAT;
    *music = config[4];
    *effects = config[5];
    return FAT_OK;
}

int fat_settings_write(struct fat_volume *v, sector_writer write,
                       uint8_t music, uint8_t effects)
{
    if (!write || music > 7 || effects > 7)
        return FAT_RANGE;
    struct fat_file file;
    int status = settings_entry(v, &file);
    uint32_t data_sector;
    if (!status) {
        if (file.size != 8 || !valid_cluster(v, file.cluster))
            return FAT_FORMAT;
        data_sector = v->start + v->data +
                      (file.cluster - 2) * v->sectors_per_cluster;
    } else if (status == FAT_NOT_FOUND) {
        uint32_t directory_cluster, free_cluster = 0, entry_sector;
        unsigned entry_offset;
        status = games_cluster(v, &directory_cluster);
        if (status)
            return status;
        status = directory_free_slot(v, directory_cluster, &entry_sector, &entry_offset);
        if (status)
            return status;
        for (uint32_t cluster = 2; cluster - 2 < v->clusters; ++cluster) {
            uint32_t value;
            status = fat_value(v, cluster, &value);
            if (status)
                return status;
            if (!value) {
                free_cluster = cluster;
                break;
            }
        }
        if (!free_cluster)
            return FAT_RANGE;
        data_sector = v->start + v->data +
                      (free_cluster - 2) * v->sectors_per_cluster;
        for (unsigned i = 0; i < 512; ++i)
            v->sector[i] = 0;
        v->sector[0] = 'L'; v->sector[1] = '9';
        v->sector[2] = 'C'; v->sector[3] = 'F';
        v->sector[4] = music; v->sector[5] = effects;
        v->sector[6] = 1;
        uint8_t check = 0xa5;
        for (unsigned i = 0; i < 7; ++i)
            check ^= v->sector[i];
        v->sector[7] = check;
        if (write(v->context, data_sector, v->sector) ||
            v->read(v->context, data_sector, v->sector) ||
            v->sector[0] != 'L' || v->sector[7] != check)
            return FAT_IO;
        status = set_fat_value(v, write, free_cluster,
                               v->fat32 ? 0x0fffffffu : 0xffffu);
        if (status)
            return status;
        status = read_relative(v, entry_sector - v->start);
        if (status)
            return status;
        uint8_t *entry = v->sector + entry_offset;
        for (unsigned i = 0; i < 32; ++i)
            entry[i] = 0;
        static const uint8_t name[11] = {
            'L', 'U', 'N', 'A', 'S', 'E', 'T', ' ', 'C', 'F', 'G'
        };
        for (unsigned i = 0; i < 11; ++i)
            entry[i] = name[i];
        entry[11] = 0x20;
        if (v->fat32) {
            entry[20] = (uint8_t)(free_cluster >> 16);
            entry[21] = (uint8_t)(free_cluster >> 24);
        }
        entry[26] = (uint8_t)free_cluster;
        entry[27] = (uint8_t)(free_cluster >> 8);
        entry[28] = 8;
        if (write(v->context, entry_sector, v->sector) ||
            v->read(v->context, entry_sector, v->sector) ||
            v->sector[entry_offset] != 'L')
            return FAT_IO;
        return FAT_OK;
    } else {
        return status;
    }

    for (unsigned i = 0; i < 512; ++i)
        v->sector[i] = 0;
    v->sector[0] = 'L'; v->sector[1] = '9';
    v->sector[2] = 'C'; v->sector[3] = 'F';
    v->sector[4] = music; v->sector[5] = effects;
    v->sector[6] = 1;
    uint8_t check = 0xa5;
    for (unsigned i = 0; i < 7; ++i)
        check ^= v->sector[i];
    v->sector[7] = check;
    if (write(v->context, data_sector, v->sector) ||
        v->read(v->context, data_sector, v->sector) ||
        v->sector[0] != 'L' || v->sector[4] != music ||
        v->sector[5] != effects || v->sector[7] != check)
        return FAT_IO;
    return FAT_OK;
}
