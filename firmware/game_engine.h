#ifndef GAME_ENGINE_H
#define GAME_ENGINE_H

#include <stdint.h>

struct flight {
    int32_t x, y, vx, vy, angle, fuel;
    int32_t x_remainder, y_remainder, vx_remainder, vy_remainder, fuel_remainder;
    int32_t thrusting;
};

/* Bits of game.cause: every touchdown check that failed. */
enum {
    GAME_FAIL_PAD = 1,
    GAME_FAIL_VERTICAL = 2,
    GAME_FAIL_HORIZONTAL = 4,
    GAME_FAIL_TILT = 8,
};

struct game {
    struct flight ship;
    int32_t terrain[25];
    uint32_t pad_start[3], pad_end[3];
    uint32_t random, score, level, capsules, outcome;
    /* Result of the last touchdown: points it earned and the failed checks. */
    uint32_t gained, cause;
};

void game_new(struct game *game, uint32_t seed);
void game_level(struct game *game);
void game_physics(struct game *game, unsigned held);
int game_touchdown(struct game *game);
int32_t game_ground(const struct game *game, int32_t x);
int32_t game_sine(int32_t angle);
int32_t game_limit_vy(unsigned level);
int32_t game_limit_vx(unsigned level);
int32_t game_limit_angle(unsigned level);

#endif
