/* Checks src/c/libc/divdi3.c against the PC's 64-bit division.
   Build and run on the PC (WSL), from the repo root:
       gcc -O2 -o build/divdi3_test src/c/libc/test/divdi3_test.c && build/divdi3_test
   Prints PASS or the first differences. */
#include <stdio.h>
#include <stdint.h>

#define DI(name) my##name
#include "../divdi3.c"

static uint64_t state = 0x2545F4914F6CDD1Dull;
static uint64_t rnd(void)
{
    state ^= state << 13;
    state ^= state >> 7;
    state ^= state << 17;
    return state;
}

/* Random widths, so small, 32-bit and full 64-bit numbers all show up */
static uint64_t pick(void)
{
    uint64_t v = rnd();
    switch (rnd() % 5) {
    case 0: return v >> (rnd() % 64);
    case 1: return v & 0xFFFFFFFF;
    case 2: return v & 0xFFFF;
    case 3: return (uint64_t)(int64_t)(int32_t)v << 16;        /* FixedDiv's numerator */
    default: return v;
    }
}

int main(void)
{
    long checks = 0;
    int errors = 0;
    for (long i = 0; i < 3000000; i++) {
        uint64_t n = pick(), d = pick();
        if (d == 0)
            continue;
        uint64_t got[4] = { my__udivdi3(n, d), my__umoddi3(n, d) }, want[4] = { n / d, n % d };
        int64_t sn = (int64_t)n, sd = (int64_t)d;
        int signed_ok = !(sn == INT64_MIN && sd == -1);         /* overflow: undefined in C */
        if (signed_ok) {
            got[2] = (uint64_t)my__divdi3(sn, sd);
            got[3] = (uint64_t)my__moddi3(sn, sd);
            want[2] = (uint64_t)(sn / sd);
            want[3] = (uint64_t)(sn % sd);
        }
        for (int k = 0; k < (signed_ok ? 4 : 2); k++, checks++)
            if (got[k] != want[k] && errors++ < 10)
                printf("FAIL op %d: %llX, %llX -> %llX, expected %llX\n", k,
                       (unsigned long long)n, (unsigned long long)d,
                       (unsigned long long)got[k], (unsigned long long)want[k]);
    }
    if (errors)
        printf("FAILED: %d of %ld checks\n", errors, checks);
    else
        printf("PASS: %ld checks of __udivdi3, __umoddi3, __divdi3, __moddi3\n", checks);
    return errors != 0;
}
