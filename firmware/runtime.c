#include <stddef.h>
#include <stdint.h>

void *memset(void *destination, int value, size_t count)
{
    volatile uint8_t *bytes = destination;
    while (count--)
        *bytes++ = (uint8_t)value;
    return destination;
}

void *memcpy(void *destination, const void *source, size_t count)
{
    volatile uint8_t *target = destination;
    const volatile uint8_t *input = source;
    while (count--)
        *target++ = *input++;
    return destination;
}
