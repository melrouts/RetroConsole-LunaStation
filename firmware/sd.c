#include "sd.h"
#include "mmio.h"

static uint32_t spi_control;
static int high_capacity;
static int io_error;

static uint8_t exchange(uint8_t value)
{
    SD_DATA = value;
    SD_COMMAND = spi_control | 1u;
    unsigned timeout = 10000;
    while ((SD_STATUS & 1u) && --timeout) {
    }
    if (!timeout || (SD_STATUS & 4u))
        io_error = 1;
    return (uint8_t)SD_DATA;
}

static void release_card(void)
{
    spi_control |= 2u;
    SD_COMMAND = spi_control;
    (void)exchange(0xff);
}

static uint8_t command(uint8_t index, uint32_t argument)
{
    release_card();
    spi_control &= ~2u;
    SD_COMMAND = spi_control;
    (void)exchange(0xff);
    (void)exchange((uint8_t)(0x40u | index));
    for (unsigned shift = 32; shift; shift -= 8)
        (void)exchange((uint8_t)(argument >> (shift - 8)));
    (void)exchange(index == 0 ? 0x95 : index == 8 ? 0x87 : 0x01);
    for (unsigned retry = 0; retry < 16; ++retry) {
        uint8_t response = exchange(0xff);
        if (!(response & 0x80))
            return response;
    }
    io_error = 1;
    return 0xff;
}

int sd_initialize(void)
{
    io_error = 0;
    high_capacity = 0;
    spi_control = (34u << 8) | 2u;
    SD_COMMAND = spi_control | 4u;
    for (unsigned i = 0; i < 10; ++i)
        (void)exchange(0xff);
    if (command(0, 0) != 1)
        goto failed;
    uint8_t r1 = command(8, 0x1aa);
    int version2 = r1 == 1;
    if (version2) {
        uint32_t response = 0;
        for (unsigned i = 0; i < 4; ++i)
            response = (response << 8) | exchange(0xff);
        if (response != 0x1aa)
            goto failed;
    } else if (r1 != 5) {
        goto failed;
    }
    uint32_t start = FRAME_COUNTER;
    unsigned attempt;
    for (attempt = 0; attempt < 2000; ++attempt) {
        if (command(55, 0) > 1)
            goto failed;
        r1 = command(41, version2 ? 0x40000000u : 0);
        if (r1 == 0)
            break;
        if (r1 != 1 || FRAME_COUNTER - start >= 60)
            goto failed;
        release_card();
        for (unsigned delay = 0; delay < 32; ++delay)
            (void)exchange(0xff);
    }
    if (attempt == 2000 || command(58, 0))
        goto failed;
    uint32_t ocr = 0;
    for (unsigned i = 0; i < 4; ++i)
        ocr = (ocr << 8) | exchange(0xff);
    if (!(ocr & 0x80000000u) || !(ocr & 0x00ff8000u))
        goto failed;
    high_capacity = version2 && (ocr & 0x40000000u);
    if (!high_capacity && command(16, 512))
        goto failed;
    release_card();
    spi_control = (2u << 8) | 2u;
    SD_COMMAND = spi_control;
    return io_error ? -1 : 0;
failed:
    release_card();
    return -1;
}

int sd_write_sector(void *context, uint32_t lba, const uint8_t sector[512])
{
    (void)context;
    if (io_error || (!high_capacity && lba > UINT32_MAX / 512u))
        return -1;
    if (command(24, high_capacity ? lba : lba * 512u))
        goto failed;
    (void)exchange(0xff);
    (void)exchange(0xfe);
    uint16_t crc = 0;
    for (unsigned i = 0; i < 512; ++i) {
        uint8_t value = sector[i];
        (void)exchange(value);
        crc ^= (uint16_t)value << 8;
        for (unsigned bit = 0; bit < 8; ++bit)
            crc = (uint16_t)((crc << 1) ^ ((crc & 0x8000) ? 0x1021 : 0));
    }
    (void)exchange((uint8_t)(crc >> 8));
    (void)exchange((uint8_t)crc);
    uint8_t response = 0xff;
    for (unsigned i = 0; i < 16 && response == 0xff; ++i)
        response = exchange(0xff);
    if ((response & 0x1f) != 5)
        goto failed;
    uint32_t start = FRAME_COUNTER;
    for (unsigned retry = 0; retry < 200000; ++retry) {
        if (exchange(0xff) == 0xff) {
            release_card();
            return io_error ? -1 : 0;
        }
        if (io_error || FRAME_COUNTER - start >= 120)
            break;
    }
failed:
    release_card();
    return -1;
}

int sd_read_sector(void *context, uint32_t lba, uint8_t sector[512])
{
    (void)context;
    if (io_error || (!high_capacity && lba > UINT32_MAX / 512u))
        return -1;
    if (command(17, high_capacity ? lba : lba * 512u))
        goto failed;
    uint32_t start = FRAME_COUNTER;
    unsigned retry;
    for (retry = 0; retry < 100000; ++retry) {
        uint8_t token = exchange(0xff);
        if (token == 0xfe)
            break;
        if (token != 0xff || FRAME_COUNTER - start >= 60 || io_error)
            goto failed;
    }
    if (retry == 100000)
        goto failed;
    uint16_t crc = 0;
    for (unsigned i = 0; i < 512; ++i) {
        sector[i] = exchange(0xff);
        crc ^= (uint16_t)sector[i] << 8;
        for (unsigned bit = 0; bit < 8; ++bit)
            crc = (uint16_t)((crc << 1) ^ ((crc & 0x8000) ? 0x1021 : 0));
    }
    uint16_t received_crc = (uint16_t)exchange(0xff) << 8;
    received_crc |= exchange(0xff);
    release_card();
    return io_error || crc != received_crc ? -1 : 0;
failed:
    release_card();
    return -1;
}
