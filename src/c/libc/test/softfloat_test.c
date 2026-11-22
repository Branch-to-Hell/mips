/* Checks src/c/libc/softfloat.c against the PC's FPU (IEEE 754, round to nearest even).
   Build and run on the PC (WSL), from the repo root:
       gcc -O2 -o build/softfloat_test src/c/libc/test/softfloat_test.c && build/softfloat_test
   The helpers are compiled for the PC with their names prefixed (my__addsf3 ...), and every
   result must have the same bits as the FPU's (any NaN matches any NaN). Prints PASS or the
   first differences. */
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>

#define SF(name) my##name
#include "../softfloat.c"

static uint64_t state = 0x9E3779B97F4A7C15ull;
static uint32_t rnd(void)
{
    state ^= state << 13;
    state ^= state >> 7;
    state ^= state << 17;
    return (uint32_t)(state >> 16);
}

static float as_f(uint32_t u) { float f; memcpy(&f, &u, 4); return f; }
static uint32_t as_u(float f) { uint32_t u; memcpy(&u, &f, 4); return u; }
static uint64_t as_u64(double d) { uint64_t u; memcpy(&u, &d, 8); return u; }
static int is_nan32(uint32_t u) { return (u & 0x7FFFFFFF) > 0x7F800000; }
static int is_nan64(uint64_t u) { return (u & ~(1ull << 63)) > 0x7FF0000000000000ull; }

static const uint32_t special[] = {
    0x00000000, 0x80000000, 0x3F800000, 0xBF800000, 0x7F800000, 0xFF800000, 0x7FC00000,
    0x00000001, 0x80000001, 0x007FFFFF, 0x00800000, 0x7F7FFFFF, 0xFF7FFFFF, 0x3F7FFFFF,
    0x4B800000, 0x4F000000, 0xCF000000, 0x34000000, 0x00400000, 0x3EAAAAAB, 0x40490FDB,
};
#define NSPECIAL (sizeof special / sizeof special[0])

/* Mostly random bits, sometimes a special value, sometimes close to the other operand
   (cancellation in subtraction, ties in rounding) */
static uint32_t pick(uint32_t other)
{
    switch (rnd() % 8) {
    case 0: return special[rnd() % NSPECIAL];
    case 1: return other ^ (rnd() & 0xFF);
    case 2: return (other & 0xFF800000) | (rnd() & 0x007FFFFF);
    case 3: return rnd() & 0x80FFFFFF;                  /* tiny: subnormal results */
    default: return rnd();
    }
}

static int errors;
static void report(const char *op, uint32_t a, uint32_t b, uint64_t got, uint64_t want)
{
    if (errors++ < 10)
        printf("FAIL %s(%08X, %08X) = %llX, expected %llX\n", op, a, b,
               (unsigned long long)got, (unsigned long long)want);
}

int main(void)
{
    const long N = 2000000;
    long checks = 0;
    for (long i = 0; i < N; i++) {
        uint32_t a = pick(0), b = pick(a);
        float fa = as_f(a), fb = as_f(b);
        struct { const char *name; uint32_t got, want; } ops[] = {
            { "add", as_u(my__addsf3(fa, fb)), as_u(fa + fb) },
            { "sub", as_u(my__subsf3(fa, fb)), as_u(fa - fb) },
            { "mul", as_u(my__mulsf3(fa, fb)), as_u(fa * fb) },
            { "div", as_u(my__divsf3(fa, fb)), as_u(fa / fb) },
        };
        for (int k = 0; k < 4; k++, checks++)
            if (ops[k].got != ops[k].want && !(is_nan32(ops[k].got) && is_nan32(ops[k].want)))
                report(ops[k].name, a, b, ops[k].got, ops[k].want);

        uint64_t got64 = as_u64(my__extendsfdf2(fa)), want64 = as_u64((double)fa);
        if (got64 != want64 && !(is_nan64(got64) && is_nan64(want64)))
            report("extend", a, 0, got64, want64);

        double da = (double)fa, db = (double)fb;
        if (rnd() & 1) { uint64_t r = ((uint64_t)rnd() << 32) | rnd(); memcpy(&da, &r, 8); }
        int lt = my__ltdf2(da, db);
        int want_lt = da < db;
        if ((lt < 0) != want_lt || ((da == db) && lt != 0))
            report("ltdf2", a, b, (uint64_t)lt, (uint64_t)want_lt);

        int32_t n = (int32_t)rnd() >> (rnd() % 32);
        uint32_t gotf = as_u(my__floatsisf(n)), wantf = as_u((float)n);
        if (gotf != wantf)
            report("floatsisf", (uint32_t)n, 0, gotf, wantf);

        if (!is_nan32(a) && fa > -2147483648.0f && fa < 2147483648.0f) {   /* in range: C defines it */
            int32_t gi = my__fixsfsi(fa), wi = (int32_t)fa;
            if (gi != wi)
                report("fixsfsi", a, 0, (uint32_t)gi, (uint32_t)wi);
        }
        checks += 4;
    }
    if (errors)
        printf("FAILED: %d of %ld checks\n", errors, checks);
    else
        printf("PASS: %ld checks of add, sub, mul, div, extend, ltdf2, floatsisf, fixsfsi\n", checks);
    return errors != 0;
}
