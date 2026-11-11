#include "game_engine.h"
#include "mmio.h"

enum { PLAY, MAIN_SCREEN, DEMO, LANDED, CRASHED, GAME_OVER, EXIT_CONFIRM,
       LUNA_MEMORIAL, APOLLO_MEMORIAL };
static struct game game;
static unsigned state, age;
static uint32_t frame;
static uint32_t best;

#ifndef BOOT_MENU_ENTRY
#define BOOT_MENU_ENTRY 0x00010000u
#endif

static __attribute__((noreturn)) void return_to_console_menu(void)
{
#if defined(__riscv)
    __asm__ volatile ("fence" ::: "memory");
#else
    __asm__ volatile ("" ::: "memory");
#endif
    ((void (*)(void))(uintptr_t)BOOT_MENU_ENTRY)();
    for (;;) {
    }
}

static int console_return_requested(unsigned current_state, uint32_t pressed)
{
    return current_state == MAIN_SCREEN && (pressed & 8u);
}

static __attribute__((noinline)) void fail(void)
{
    BOOT_STATUS = 2;
    for (;;) {
    }
}

static void wait_snapshot(void)
{
    unsigned timeout = 1000000;
    while ((VIDEO_STATUS & 2u) && --timeout) {
    }
    if (!timeout || (VIDEO_STATUS & 4u))
        fail();
}

static uint32_t bcd(uint32_t value)
{
    uint32_t result = 0;
    for (unsigned digit = 0; digit < 8; ++digit) {
        result |= (value % 10u) << (digit * 4);
        value /= 10u;
    }
    return result;
}

static uint32_t telemetry(void)
{
    struct flight *f = &game.ship;
    int32_t ax = f->vx < 0 ? -f->vx : f->vx;
    int32_t ay = f->vy < 0 ? -f->vy : f->vy;
    int32_t vx = ax / 256, vy = ay / 256;
    uint32_t square = (uint32_t)(vx * vx + vy * vy), speed = 0;
    for (uint32_t bit = 2048; bit; bit >>= 1) {
        uint32_t trial = speed | bit;
        if (trial * trial <= square)
            speed = trial;
    }
    if (speed > 999)
        speed = 999;
    int32_t altitude = (game_ground(&game, f->x) - f->y - 11 * 256) / 256;
    if (altitude < 0)
        altitude = 0;
    uint32_t height = bcd((uint32_t)altitude);
    uint32_t direction = (f->vx < 0 ? 1u : 0u) | (f->vy < 0 ? 2u : 0u);
    if (vx * 2 < vy)
        direction |= 4;
    else if (vy * 2 < vx)
        direction |= 8;
    /* Clockwise from north; a zero speed is drawn as a stationary dot. */
    static const uint8_t compass[16] = {3,5,1,7,4,4,0,0,2,6,2,6,0,0,0,0};
    uint32_t heading = compass[direction];
    VIDEO_XY = (uint32_t)(f->x * 4 / (5 * 256)) |
               ((((uint32_t)f->angle + 1024u) & 65535u) >> 11) << 10 |
               ((heading >> 2) & 1u) << 15 |
               (uint32_t)(f->y * 4 / (5 * 256)) << 16 |
               (heading & 3u) << 26 | (height >> 8) << 28;
    VIDEO_HUD = (bcd((uint32_t)f->fuel / 256u) & 0xffffu) |
                (bcd(game.level) & 0xffu) << 16 | game.capsules << 24 |
                ((height >> 4) & 15u) << 28;
    int32_t limit_x = game_limit_vx(game.level), limit_y = game_limit_vy(game.level);
    uint32_t risk = ax > limit_x || ay > limit_y ? 2 :
                    ax * 4 >= limit_x * 3 || ay * 4 >= limit_y * 3 ? 1 : 0;
    return bcd(speed) << 8 | (height & 15u) << 20 | risk << 2;
}

static void publish(int terrain_changed)
{
    wait_snapshot();
    if (terrain_changed) {
        for (unsigned x = 0; x < 640; ++x) {
            int32_t ground = game_ground(&game, (int32_t)x * 5 * 256 / 4);
            TERRAIN_COLUMN(x) = (uint32_t)(ground * 4 / (5 * 256));
        }
    }
    struct flight *f = &game.ship;
    uint32_t fuel = (uint32_t)f->fuel / 256u;
    uint32_t maximum = game.level <= 11 ? 1200 - (game.level - 1) * 55 : 620;
    if (maximum < 620)
        maximum = 620;
    VIDEO_FLAGS = telemetry() | 1u | (f->thrusting ? 2u : 0) | state << 4 |
                  (fuel * 100u / maximum) << 24;
    VIDEO_SCORE = bcd(state == MAIN_SCREEN || state == DEMO ? best : game.score);
    /*
     * The landing result rides in the unused bits [15:10] and [31:26] of the pad
     * words: 12 bits per pad, 24 bits in all = five BCD digits of points earned
     * and the four failure bits. Only the end-of-flight screens carry it.
     */
    uint32_t result = 0;
    if (state == LANDED || state == CRASHED || state == GAME_OVER)
        result = (bcd(game.gained) & 0xfffffu) | game.cause << 20;
    for (unsigned pad = 0; pad < 3; ++pad) {
        uint32_t left = game.pad_start[pad] * 640u / 24u;
        uint32_t right = game.pad_end[pad] * 640u / 24u;
        uint32_t field = (result >> (pad * 12)) & 0xfffu;
        MMIO32(0x50 + pad * 4) = left | right << 16 | (field & 63u) << 10 | (field >> 6) << 26;
    }
    VIDEO_COMMIT = 1;
}

static void enter(unsigned next)
{
    state = next;
    age = 0;
}

static void publish_audio(void)
{
    unsigned audio = GAME_AUDIO_IDLE;
    if (state == MAIN_SCREEN || state == LUNA_MEMORIAL || state == APOLLO_MEMORIAL) {
        audio = GAME_AUDIO_ATTRACT;
    } else if (state == PLAY || state == DEMO) {
        if (game.outcome == 1)
            audio = GAME_AUDIO_LANDED;
        else if (game.outcome == 2)
            audio = GAME_AUDIO_CRASHED;
        else if (state == DEMO)
            audio = game.ship.thrusting ? GAME_AUDIO_DEMO_THRUST : GAME_AUDIO_DEMO;
        else
            audio = game.ship.thrusting ? GAME_AUDIO_FLYING_THRUST : GAME_AUDIO_FLYING;
    } else if (state == EXIT_CONFIRM) {
        audio = GAME_AUDIO_FLYING;
    } else if (state == LANDED) {
        audio = GAME_AUDIO_LANDED;
    } else if (state == CRASHED || state == GAME_OVER) {
        audio = GAME_AUDIO_CRASHED;
    }
    AUDIO_LINK = audio;
}

static unsigned demo_controls(void)
{
    int32_t target = (int32_t)(game.pad_start[0] + game.pad_end[0]) * (800 * 256) / 48;
    int32_t error = target - game.ship.x;
    int32_t target_angle = error > 30 * 256 ? 1200 : error < -30 * 256 ? -1200 : 0;
    if (game.ship.vx > 12 * 256)
        target_angle = -1200;
    if (game.ship.vx < -12 * 256)
        target_angle = 1200;
    unsigned held = game.ship.angle < target_angle - 200 ? 4 :
                    game.ship.angle > target_angle + 200 ? 1 : 0;
    int32_t altitude = game_ground(&game, game.ship.x) - game.ship.y - 11 * 256;
    if (game.ship.vy > 22 * 256 || (altitude < 80 * 256 && game.ship.vy > 7 * 256))
        held |= 2;
    return held;
}

int main(void)
{
    if (ABI_VERSION != 1 || HARDWARE_VERSION != 1 || AUDIO_LINK != AUDIO_LINK_VERSION)
        fail();
    game_new(&game, 42);
    enter(MAIN_SCREEN);
    INPUT_EVENT = 0xff;
    publish_audio();
    publish(1);
    BOOT_STATUS = 7;
    frame = FRAME_COUNTER;
    for (;;) {
        wait_snapshot();
        unsigned timeout = 1000000;
        while (FRAME_COUNTER == frame && --timeout) {
        }
        if (!timeout)
            fail();
        frame = FRAME_COUNTER;
        unsigned pressed = INPUT_EVENT & 15u;
        unsigned held = INPUT_STATE & 15u;
        INPUT_EVENT = 0xff;
        int terrain_changed = 0;
        ++age;
        if (console_return_requested(state, pressed)) {
            return_to_console_menu();
        } else if ((state == MAIN_SCREEN || state == DEMO || state == GAME_OVER ||
             state == LUNA_MEMORIAL || state == APOLLO_MEMORIAL) && (pressed & 2)) {
            game_new(&game, frame | 1u);
            terrain_changed = 1;
            enter(PLAY);
        } else if (state == MAIN_SCREEN && age >= 900) {
            enter(LUNA_MEMORIAL);
        } else if (state == LUNA_MEMORIAL && age >= 900) {
            enter(APOLLO_MEMORIAL);
        } else if (state == APOLLO_MEMORIAL && age >= 900) {
            game_new(&game, 42);
            terrain_changed = 1;
            enter(DEMO);
        } else if (state == EXIT_CONFIRM) {
            if (pressed & 2) {
                game_new(&game, 42);
                terrain_changed = 1;
                enter(MAIN_SCREEN);
            } else if (pressed & 8) {
                enter(PLAY);
            }
        } else if (state == PLAY || state == DEMO) {
            if (state == PLAY && (pressed & 8)) {
                enter(EXIT_CONFIRM);
            } else {
                game_physics(&game, state == DEMO ? demo_controls() : held);
                int outcome = game_touchdown(&game);
                if (state == DEMO && age >= 900) {
                    game_new(&game, 42);
                    terrain_changed = 1;
                    enter(MAIN_SCREEN);
                } else if (outcome && state != DEMO) {
                    if (game.score > best)
                        best = game.score;
                    enter(outcome == 1 ? LANDED : game.capsules ? CRASHED : GAME_OVER);
                }
            }
        } else if ((state == LANDED || state == CRASHED) && age >= 180) {
            if (state == LANDED && game.level < 99)
                ++game.level;
            game_level(&game);
            terrain_changed = 1;
            enter(PLAY);
        } else if (state == GAME_OVER) {
            /* 900 frames (15 s) without a button press return to the menu. */
            if ((pressed & 8) || age >= 900) {
                game_new(&game, 42);
                terrain_changed = 1;
                enter(MAIN_SCREEN);
            } else if (pressed) {
                age = 0;
            }
        }
        publish_audio();
        publish(terrain_changed);
    }
}
