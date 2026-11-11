#include "fat.h"
#include "image.h"
#include "mmio.h"
#include "sd.h"
#include "update.h"

#ifndef MAIN_RAM_BYTES
#error MAIN_RAM_BYTES is required
#endif
#ifndef STACK_BYTES
#error STACK_BYTES is required
#endif

static struct fat_volume volume;
static struct fat_file file;
static uint8_t buffer[512];
static struct update_slot slots[2];
static int selected = -1;
static int latest_slot = -1;
static int sd_ready;
static int updates_prepared = -1;
static uint32_t game_count;
static uint32_t initial_game;
extern uint8_t __update_staging[UPDATE_MAX_IMAGE];

static void fail(uint32_t status);

static uint8_t uppercase(uint8_t value)
{
    return value >= 'a' && value <= 'z' ? (uint8_t)(value - 'a' + 'A') : value;
}

static void send_text(const char *text)
{
    while (*text) {
        while (UART_STATUS & 2u) {
        }
        UART_DATA = (uint8_t)*text++;
    }
}

static void restart(void)
{
    while (UART_STATUS & 2u) {
    }
    UART_CONTROL = 1;
    for (;;) {
    }
}

static int receive(uint8_t *data, unsigned count)
{
    uint32_t start = FRAME_COUNTER;
    unsigned guard = 3000000;
    while (count) {
        uint32_t status = UART_STATUS;
        if ((status & 4u) || FRAME_COUNTER - start >= 600 || !--guard)
            return -1;
        if (status & 1u) {
            *data++ = (uint8_t)UART_DATA;
            --count;
            guard = 3000000;
        }
    }
    return 0;
}

static void serial_update(int prepared)
{
    if (prepared) {
        send_text("ERR slots\n");
        restart();
    }
    send_text("READY LUP1\n");
    uint8_t header[12];
    if (receive(header, sizeof header) || little32(header) != 0x3150554cu) {
        send_text("ERR header\n");
        restart();
    }
    uint32_t size = little32(header + 4), expected = little32(header + 8);
    if (size < 36 || size > UPDATE_MAX_IMAGE) {
        send_text("ERR size\n");
        restart();
    }
    uint8_t *staging = __update_staging;
    send_text("SEND\n");
    for (uint32_t offset = 0, index = 0; offset < size; ++index) {
        unsigned count = size - offset > 64 ? 64 : size - offset;
        if (receive(buffer, count + 6) || little16(buffer) != index ||
            (image_crc(UINT32_MAX, buffer, count + 2) ^ UINT32_MAX) !=
            little32(buffer + count + 2)) {
            send_text("ERR block\n");
            restart();
        }
        for (unsigned i = 0; i < count; ++i)
            staging[offset + i] = buffer[2 + i];
        offset += count;
        send_text("ACK\n");
    }
    if ((image_crc(UINT32_MAX, staging, size) ^ UINT32_MAX) != expected) {
        send_text("ERR crc\n");
        restart();
    }
    uint32_t generation = slots[0].generation > slots[1].generation ?
                          slots[0].generation : slots[1].generation;
    if (generation == UINT32_MAX) {
        send_text("ERR generation\n");
        restart();
    }
    unsigned target = slots[0].generation > slots[1].generation ? 1 : 0;
    send_text("WRITE\n");
    if (update_commit(&volume, sd_write_sector, &slots[target], staging, size, generation + 1)) {
        send_text("ERR write\n");
        restart();
    }
    send_text("DONE\n");
    restart();
}

static int read_image(uint32_t offset, uint8_t *data, uint32_t count)
{
    return selected >= 0 ? update_read(&volume, &slots[selected], offset, data, count) :
                           fat_read_file(&file, offset, data, count);
}

static int mount_card(void)
{
    sd_ready = 0;
    latest_slot = -1;
    updates_prepared = -1;
    if (sd_initialize() || fat_mount(&volume, sd_read_sector, 0))
        return -1;
    sd_ready = 1;
    updates_prepared = update_prepare(&volume, slots);
    if (!updates_prepared) {
        for (unsigned i = 0; i < 2; ++i) {
            int valid = update_validate(&volume, &slots[i]);
            if (valid < 0) {
                sd_ready = 0;
                return -1;
            }
            if (!valid && (latest_slot < 0 ||
                           slots[i].generation > slots[latest_slot].generation))
                latest_slot = (int)i;
        }
    }
    if (fat_game_count(&volume, &game_count)) {
        sd_ready = 0;
        return -1;
    }
    initial_game = 0;
    for (uint32_t i = 0; i < game_count; ++i) {
        struct fat_file candidate;
        if (fat_game_at(&volume, i, &candidate))
            continue;
        static const char lunar[] = "LUNAR.BIN";
        unsigned j = 0;
        while (lunar[j] && uppercase((uint8_t)candidate.name[j]) ==
                           uppercase((uint8_t)lunar[j]))
            ++j;
        if (!lunar[j] && !candidate.name[j]) {
            initial_game = i;
            break;
        }
    }
    return 0;
}

static uint32_t title_word(const struct fat_file *game, unsigned offset)
{
    uint32_t word = 0;
    for (unsigned i = 0; i < 4; ++i) {
        unsigned position = offset + i;
        uint8_t character = ' ';
        if (position < 8 && game) {
            int extension = 0;
            for (unsigned j = 0; j <= position; ++j)
                if (game->name[j] == '.')
                    extension = 1;
            character = extension ? ' ' : (uint8_t)game->name[position];
            if (!character)
                character = ' ';
            if (character >= 'a' && character <= 'z')
                character = (uint8_t)(character - 'a' + 'A');
        }
        word |= (uint32_t)character << (i * 8);
    }
    return word;
}

static void wait_snapshot(void)
{
    unsigned timeout = 1000000;
    while ((VIDEO_STATUS & 2u) && --timeout) {
    }
    if (!timeout || (VIDEO_STATUS & 4u))
        fail(7);
}

static void publish_menu(uint32_t game_index, uint8_t music, uint8_t effects,
                         int settings, unsigned focus, unsigned status)
{
    struct fat_file titles[3];
    int valid[3] = {0, 0, 0};
    if (sd_ready && game_count) {
        for (unsigned row = 0; row < 3; ++row) {
            if ((row == 0 && game_index == 0) ||
                (row == 2 && game_index + 1 >= game_count))
                continue;
            uint32_t index = row == 0 ? game_index - 1 :
                             row == 1 ? game_index : game_index + 1;
            valid[row] = !fat_game_at(&volume, index, &titles[row]);
        }
    }
    wait_snapshot();
    VIDEO_XY = title_word(valid[0] ? &titles[0] : 0, 0);
    VIDEO_HUD = title_word(valid[0] ? &titles[0] : 0, 4);
    VIDEO_SCORE = title_word(valid[1] ? &titles[1] : 0, 0);
    MMIO32(0x50) = title_word(valid[1] ? &titles[1] : 0, 4);
    MMIO32(0x54) = title_word(valid[2] ? &titles[2] : 0, 0);
    MMIO32(0x58) = title_word(valid[2] ? &titles[2] : 0, 4);
    VIDEO_FLAGS = 1u | 9u << 4 | (settings ? 8u : 0) |
                  (focus & 1u) << 1 | (status & 15u) << 12 |
                  (uint32_t)music << 16 | (uint32_t)effects << 24;
    VIDEO_COMMIT = 1;
    AUDIO_CONFIG = (uint32_t)music << 3 | effects;
    AUDIO_LINK = GAME_AUDIO_ATTRACT;
}

static int load_game(struct fat_file *selected_file)
{
    file.volume = selected_file->volume;
    file.cluster = selected_file->cluster;
    file.size = selected_file->size;
    for (unsigned i = 0; i < sizeof file.name; ++i)
        file.name[i] = selected_file->name[i];
    selected = -1;
    if (latest_slot >= 0) {
        static const char lunar[] = "LUNAR.BIN";
        unsigned i = 0;
        while (lunar[i] && uppercase((uint8_t)file.name[i]) ==
                           uppercase((uint8_t)lunar[i]))
            ++i;
        if (!lunar[i] && !file.name[i])
            selected = latest_slot;
    }
    uint8_t header[32];
    uint32_t size = selected >= 0 ? slots[selected].size : file.size;
    if (read_image(0, header, sizeof header))
        return 3;
    struct game_image image;
    int status = image_header(header, size, MAIN_RAM_BYTES, STACK_BYTES, 1, &image);
    if (status)
        return status;
    uint32_t crc = UINT32_MAX;
    for (uint32_t offset = 0; offset < image.size;) {
        uint32_t count = image.size - offset;
        if (count > sizeof buffer)
            count = sizeof buffer;
        if (read_image(offset + 32, buffer, count))
            return 3;
        crc = image_crc(crc, buffer, count);
        volatile uint8_t *destination = (volatile uint8_t *)(uintptr_t)(image.load + offset);
        for (uint32_t i = 0; i < count; ++i)
            destination[i] = buffer[i];
        offset += count;
    }
    if ((crc ^ UINT32_MAX) != image.payload_crc)
        return 5;
    __asm__ volatile ("fence" ::: "memory");
    ((void (*)(void))(uintptr_t)image.entry)();
    return 4;
}

static void wait_next_frame(uint32_t *frame)
{
    unsigned timeout = 1000000;
    while (FRAME_COUNTER == *frame && --timeout) {
    }
    if (!timeout)
        fail(7);
    *frame = FRAME_COUNTER;
}

static void run_menu(void)
{
    uint8_t music = 7, effects = 7;
    uint32_t selected_game = initial_game;
    uint32_t frame = FRAME_COUNTER;
    unsigned focus = 0, retry = 0, status = 0;
    int settings = 0;
    if (sd_ready) {
        if (fat_settings_read(&volume, &music, &effects))
            music = effects = 7;
        if (!game_count)
            status = 2;
    } else {
        status = 1;
    }
    INPUT_EVENT = 0xff;
    BOOT_STATUS = 7;
    for (;;) {
        wait_next_frame(&frame);
        unsigned pressed = INPUT_EVENT & 15u;
        INPUT_EVENT = 0xff;
        if ((UART_STATUS & 8u) && sd_ready)
            serial_update(updates_prepared);

        if (!sd_ready && ++retry >= 300) {
            retry = 0;
            if (!mount_card()) {
                selected_game = initial_game;
                status = game_count ? 0 : 2;
                if (!fat_settings_read(&volume, &music, &effects))
                    status = game_count ? 0 : 2;
            }
        }
        if (settings) {
            if (pressed & 2u)
                focus ^= 1u;
            if (pressed & 1u) {
                uint8_t *value = focus ? &effects : &music;
                if (*value)
                    --*value;
            }
            if (pressed & 4u) {
                uint8_t *value = focus ? &effects : &music;
                if (*value < 7)
                    ++*value;
            }
            if (pressed & 8u) {
                int save_failed = sd_ready &&
                    fat_settings_write(&volume, sd_write_sector, music, effects);
                if (save_failed || !sd_ready)
                    status = 3;
                settings = 0;
                focus = 0;
                if (sd_ready && !save_failed)
                    status = game_count ? 0 : 2;
            }
        } else if (pressed & 8u) {
            settings = 1;
            focus = 0;
            status = sd_ready ? 0 : 1;
        } else if (sd_ready && game_count) {
            if (pressed & 1u)
                selected_game = selected_game ? selected_game - 1 : game_count - 1;
            if (pressed & 4u)
                selected_game = selected_game + 1 == game_count ? 0 : selected_game + 1;
            if (pressed & 2u) {
                struct fat_file game;
                if (!fat_game_at(&volume, selected_game, &game)) {
                    int error = load_game(&game);
                    status = error ? 4 : 0;
                } else {
                    sd_ready = 0;
                    status = 1;
                }
            }
        }
        publish_menu(selected_game, music, effects, settings, focus, status);
    }
}

static void fail(uint32_t status)
{
    BOOT_STATUS = status;
    for (;;) {
    }
}

int main(void)
{
    selected = -1;
    if (HARDWARE_VERSION != 1 || ABI_VERSION != 1)
        fail(6);
    (void)mount_card();
    if (UART_STATUS & 8u) {
        if (!sd_ready) {
            send_text("ERR sd\n");
            restart();
        }
        serial_update(updates_prepared);
    }
    run_menu();
    fail(4);
}
