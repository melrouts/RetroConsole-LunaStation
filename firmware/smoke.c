#include "mmio.h"

static volatile uint32_t scratch[8];
static volatile uint32_t data_sentinel = 0x12345678u;

static void fail(uint32_t status)
{
    BOOT_STATUS = status;
    for (;;) {
    }
}

int main(void)
{
    if (ABI_VERSION != 1 || HARDWARE_VERSION != 1)
        fail(6);
    if (data_sentinel != 0x12345678u)
        fail(2);
    for (unsigned i = 0; i < 8; ++i) {
        if (scratch[i] != 0)
            fail(2);
        scratch[i] = 0xa5a50000u + i;
    }
    for (unsigned i = 0; i < 8; ++i) {
        if (scratch[i] != 0xa5a50000u + i)
            fail(2);
    }
    volatile uint8_t *bytes = (volatile uint8_t *)&scratch[0];
    bytes[1] = 0x3c;
    if (scratch[0] != 0xa5a53c00u)
        fail(2);
    AUDIO_PERIOD = 27;
    AUDIO_CONTROL = 1;
    if (AUDIO_PERIOD != 27 || AUDIO_CONTROL != 1)
        fail(2);
    if (INPUT_STATE != 0 || MMIO32(0xfc) != 0)
        fail(2);
    INPUT_EVENT = 0xff;
    BOOT_STATUS = 7;
    for (;;) {
    }
}
