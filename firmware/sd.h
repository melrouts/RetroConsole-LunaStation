#ifndef SD_H
#define SD_H

#include <stdint.h>

int sd_initialize(void);
int sd_read_sector(void *context, uint32_t lba, uint8_t sector[512]);
int sd_write_sector(void *context, uint32_t lba, const uint8_t sector[512]);

#endif
