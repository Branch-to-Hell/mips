/* Minimal C library for our MIPS (TC-10): 64-bit division and remainder.
   GCC calls these for long long / and % (Doom's FixedDiv: (int64)a << 16 / b). The cross
   compiler's libgcc.a has them, but built for MIPS32: they use clz (SPECIAL2), which our
   MIPS I CPU doesn't have, and teq. So they live here, linked before -lgcc.
   When both numbers fit in 32 bits it is one divu; otherwise binary long division.
   Checked against the PC on millions of values (src/c/libc/test/divdi3_test.c). */
#include <stdint.h>

#ifndef DI
#define DI(name) name           /* the host test renames them */
#endif

/* n / d and n % d; d != 0 (division by zero gives quotient all ones, remainder n) */
static uint64_t udivmod(uint64_t n, uint64_t d, uint64_t *rem)
{
    if (d == 0) {
        if (rem) *rem = n;
        return ~0ull;
    }
    if ((n >> 32) == 0 && (d >> 32) == 0) {             /* the common case: divu */
        uint32_t n32 = (uint32_t)n, d32 = (uint32_t)d;
        if (rem) *rem = n32 % d32;
        return n32 / d32;
    }
    if (d > n) {
        if (rem) *rem = n;
        return 0;
    }
    /* Line d up under n's top bit, then subtract it bit by bit */
    int shift = 0;
    while (!(d & (1ull << 63)) && (d << 1) <= n) {
        d <<= 1;
        shift++;
    }
    uint64_t q = 0;
    for (;;) {
        q <<= 1;
        if (n >= d) {
            n -= d;
            q |= 1;
        }
        if (!shift--)
            break;
        d >>= 1;
    }
    if (rem) *rem = n;
    return q;
}

uint64_t DI(__udivdi3)(uint64_t n, uint64_t d)
{
    return udivmod(n, d, 0);
}

uint64_t DI(__umoddi3)(uint64_t n, uint64_t d)
{
    uint64_t r;
    udivmod(n, d, &r);
    return r;
}

/* Signed: the quotient rounds toward zero, the remainder has the dividend's sign (C) */
int64_t DI(__divdi3)(int64_t n, int64_t d)
{
    uint64_t un = n < 0 ? -(uint64_t)n : (uint64_t)n;
    uint64_t ud = d < 0 ? -(uint64_t)d : (uint64_t)d;
    uint64_t q = udivmod(un, ud, 0);
    return (n < 0) != (d < 0) ? -(int64_t)q : (int64_t)q;
}

int64_t DI(__moddi3)(int64_t n, int64_t d)
{
    uint64_t un = n < 0 ? -(uint64_t)n : (uint64_t)n;
    uint64_t ud = d < 0 ? -(uint64_t)d : (uint64_t)d;
    uint64_t r;
    udivmod(un, ud, &r);
    return n < 0 ? -(int64_t)r : (int64_t)r;
}
