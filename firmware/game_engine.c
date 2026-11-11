#include "game_engine.h"
#include "sine_table.h"

#define Q 256
#define WORLD (800 * Q)

static int32_t clamp(int32_t value, int32_t low, int32_t high)
{
    return value < low ? low : value > high ? high : value;
}

static int32_t absolute(int32_t value)
{
    return value < 0 ? -value : value;
}

static uint32_t random_below(struct game *g, uint32_t limit)
{
    uint32_t value = g->random;
    value ^= value << 13;
    value ^= value >> 17;
    value ^= value << 5;
    g->random = value;
    return ((value >> 16) * limit) >> 16;
}

int32_t game_sine(int32_t angle)
{
    uint32_t turn = (uint16_t)angle;
    uint32_t position = turn & 0x3fff;
    if (turn & 0x4000)
        position = 16384 - position;
    uint32_t index = position >> 8;
    int32_t value = sine_quarter[index];
    if (index < 64)
        value += (sine_quarter[index + 1] - value) * (int32_t)(position & 255) / 256;
    return turn & 0x8000 ? -value : value;
}

/* Keep the shared level curve out of line to fit the 8 KiB application RAM. */
static __attribute__((noinline)) int32_t level_limit(unsigned level, int32_t base, int32_t step)
{
    unsigned tightening = level <= 1 ? 0 : level >= 6 ? 5 : level - 1;
    return base - step * (int32_t)tightening / 5;
}

int32_t game_limit_vy(unsigned level)
{
    return level_limit(level, 48 * Q, 6 * Q);
}

int32_t game_limit_vx(unsigned level)
{
    return level_limit(level, 30 * Q, 6 * Q);
}

int32_t game_limit_angle(unsigned level)
{
    return level_limit(level, 2712, 626);
}

void game_level(struct game *g)
{
    unsigned roughness = 55 + (g->level - 1) * 9;
    if (roughness > 100)
        roughness = 100;
    int32_t minimum = 348 * Q + 207 * Q * (int32_t)(100 - roughness) / 100;
    for (unsigned i = 0; i <= 24; ++i)
        g->terrain[i] = minimum + (int32_t)random_below(g, (uint32_t)(555 * Q - minimum));
    for (unsigned zone = 0; zone < 3; ++zone) {
        int32_t span = (int32_t)(3 - zone) + (g->level <= 2 ? 1 : 0) -
                       (int32_t)((g->level - 1) / 3);
        if (span < 1)
            span = 1;
        uint32_t low = zone * 8 + 1;
        uint32_t high = (zone + 1) * 8 - (uint32_t)span - 1;
        if (high < low)
            high = low;
        uint32_t start = low + random_below(g, high - low + 1);
        g->pad_start[zone] = start;
        g->pad_end[zone] = start + (uint32_t)span;
        int32_t y = 348 * Q + (int32_t)random_below(g, 207 * Q);
        for (uint32_t i = start; i <= g->pad_end[zone]; ++i)
            g->terrain[i] = y;
    }
    struct flight *fresh = &g->ship;
    *fresh = (struct flight){0};
    fresh->x = (144 + (int32_t)random_below(g, 512)) * Q;
    fresh->y = 60 * Q;
    int32_t velocity_range = 14 * Q * (int32_t)(100 + (g->level - 1) * 16) / 100;
    fresh->vx = (int32_t)random_below(g, (uint32_t)velocity_range) - velocity_range / 2;
    fresh->vy = 6 * Q;
    fresh->fuel = clamp(1200 - (int32_t)(g->level - 1) * 55, 620, 1200) * Q;
    g->outcome = 0;
    g->gained = 0;
    g->cause = 0;
}

void game_new(struct game *g, uint32_t seed)
{
    g->random = seed ? seed : 0x9e3779b9u;
    g->score = 0;
    g->level = 1;
    g->capsules = 3;
    game_level(g);
}

int32_t game_ground(const struct game *g, int32_t x)
{
    x = clamp(x, 0, WORLD);
    uint32_t scaled = (uint32_t)x * 24;
    unsigned index = scaled / WORLD;
    if (index >= 24)
        index = 23;
    uint32_t fraction = scaled - index * WORLD;
    int32_t delta = g->terrain[index + 1] - g->terrain[index];
    uint32_t span = (uint32_t)absolute(delta);
    /*
     * Exact span * fraction / WORLD without a 64-bit division (which would pull
     * __divdi3 into the 8 KiB image). WORLD is 4096 * 50, so split the fraction
     * into 4096ths and fold the floors: floor(floor(p / 4096) / 50) = floor(p / WORLD).
     */
    uint32_t step = (span * (fraction >> 12) + ((span * (fraction & 4095u)) >> 12)) / 50u;
    return g->terrain[index] + (delta < 0 ? -(int32_t)step : (int32_t)step);
}

static int32_t tick_fraction(int32_t value, int32_t *remainder)
{
    int32_t total = value + *remainder;
    int32_t result = total / 60;
    *remainder = total - result * 60;
    return result;
}

void game_physics(struct game *g, unsigned held)
{
    if (g->outcome)
        return;
    struct flight *f = &g->ship;
    f->angle += ((held & 4) ? 365 : 0) - ((held & 1) ? 365 : 0);
    f->angle = clamp(f->angle, -24576, 24576);
    int32_t ax = 0;
    int32_t ay = 21 * Q * (int32_t)(100 + (g->level - 1) * 7) / 100;
    f->thrusting = (held & 2) && f->fuel > 0;
    if (f->thrusting) {
        ax = 62 * Q * game_sine(f->angle) / 32768;
        ay -= 62 * Q * game_sine(f->angle + 16384) / 32768;
        f->fuel -= tick_fraction(140 * Q, &f->fuel_remainder);
        if (f->fuel < 0)
            f->fuel = 0;
    }
    f->vx += tick_fraction(ax, &f->vx_remainder);
    f->vy += tick_fraction(ay, &f->vy_remainder);
    f->vx = clamp(f->vx, -2048 * Q, 2048 * Q);
    f->vy = clamp(f->vy, -2048 * Q, 2048 * Q);
    f->x += tick_fraction(f->vx, &f->x_remainder);
    f->y += tick_fraction(f->vy, &f->y_remainder);
    if (f->x < 0)
        f->x += WORLD;
    else if (f->x > WORLD)
        f->x -= WORLD;
    if (f->y < 11 * Q) {
        f->y = 11 * Q;
        f->y_remainder = 0;
        if (f->vy < 0) {
            f->vy = 0;
            f->vy_remainder = 0;
        }
    }
}

int game_touchdown(struct game *g)
{
    struct flight *f = &g->ship;
    if (g->outcome || f->y + 11 * Q < game_ground(g, f->x))
        return (int)g->outcome;
    f->y = game_ground(g, f->x) - 11 * Q;
    int pad = -1;
    uint32_t scaled = (uint32_t)clamp(f->x, 0, WORLD) * 24;
    for (unsigned i = 0; i < 3; ++i)
        if (scaled >= g->pad_start[i] * WORLD && scaled <= g->pad_end[i] * WORLD)
            pad = (int)i;
    f->thrusting = 0;
    g->cause = (pad < 0 ? GAME_FAIL_PAD : 0) |
               (f->vy > game_limit_vy(g->level) ? GAME_FAIL_VERTICAL : 0) |
               (absolute(f->vx) > game_limit_vx(g->level) ? GAME_FAIL_HORIZONTAL : 0) |
               (absolute(f->angle) > game_limit_angle(g->level) ? GAME_FAIL_TILT : 0);
    if (!g->cause) {
        int32_t softness = clamp(48 * Q - absolute(f->vy), 0, 48 * Q);
        uint32_t multiplier = 1u << (unsigned)pad;
        uint32_t numerator = (120 * multiplier + 100 * (g->level - 1)) * (48 * Q) +
                             250 * multiplier * (uint32_t)softness +
                             (uint32_t)f->fuel * 72u;
        uint32_t gained = (numerator + 24 * Q) / (48 * Q);
        g->gained = gained;
        g->score = g->score > UINT32_MAX - gained ? UINT32_MAX : g->score + gained;
        g->outcome = 1;
    } else {
        g->gained = 0;
        if (g->capsules)
            --g->capsules;
        g->outcome = 2;
    }
    return (int)g->outcome;
}
