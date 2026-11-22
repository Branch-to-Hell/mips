/* Minimal C library for our MIPS (TC-10): software floating point.
   GCC compiles float/double arithmetic with -msoft-float into calls to these helpers. The
   cross compiler's libgcc.a is built for a hard-float CPU (its __subsf3 is one sub.s, an FPU
   instruction our CPU doesn't have), so the ones a program needs live here, linked before
   -lgcc. Only what Doom calls: single precision + - * /, int <-> float, float -> double and
   double <. IEEE 754, round to nearest even, with subnormals, infinities and NaN.
   The algorithms follow Berkeley SoftFloat 3 (BSD license, John R. Hauser).
   Only integer operations on the bits: a float operation in here would call itself.
   Checked against the PC's FPU on millions of values (src/c/libc/test/softfloat_test.c). */
#include <stdint.h>

#ifndef SF
#define SF(name) name           /* the host test renames them */
#endif

typedef union { float f; uint32_t u; } f32;
typedef union { double d; uint64_t u; } f64;

#define F32_NAN 0x7FC00000u     /* the default NaN */

static uint32_t sign_of(uint32_t a) { return a >> 31; }
static int exp_of(uint32_t a) { return (a >> 23) & 0xFF; }
static uint32_t frac_of(uint32_t a) { return a & 0x007FFFFF; }
static uint32_t pack(uint32_t sign, int exp, uint32_t sig)
{
    return (sign << 31) + ((uint32_t)exp << 23) + sig;   /* sig's hidden bit carries into exp */
}

static int clz32(uint32_t a)
{
    int n = 0;
    if (!a) return 32;
    while (!(a & 0x80000000u)) { a <<= 1; n++; }
    return n;
}

/* a >> dist, with any 1 shifted out kept in bit 0 ("jamming") */
static uint32_t shift_right_jam32(uint32_t a, int dist)
{
    return dist < 31 ? (a >> dist) | ((uint32_t)(a << (-dist & 31)) != 0) : (a != 0);
}

/* sig: hidden bit at bit 30, 7 more bits below the result's last one; exp: biased - 1 */
static uint32_t round_pack(uint32_t sign, int exp, uint32_t sig)
{
    uint32_t round_bits = sig & 0x7F;
    if ((unsigned)exp >= 0xFD) {
        if (exp < 0) {                                  /* subnormal result */
            sig = shift_right_jam32(sig, -exp);
            exp = 0;
            round_bits = sig & 0x7F;
        } else if (exp > 0xFD || sig + 0x40 >= 0x80000000u) {
            return pack(sign, 0xFF, 0);                 /* overflow: infinity */
        }
    }
    sig = (sig + 0x40) >> 7;
    if (round_bits == 0x40)
        sig &= ~1u;                                     /* a tie: to even */
    if (!sig)
        exp = 0;
    return pack(sign, exp, sig);
}

static uint32_t norm_round_pack(uint32_t sign, int exp, uint32_t sig)
{
    int dist = clz32(sig) - 1;
    exp -= dist;
    if (dist >= 7 && (unsigned)exp < 0xFD)
        return pack(sign, sig ? exp : 0, sig << (dist - 7));
    return round_pack(sign, exp, sig << dist);
}

static uint32_t add_mags(uint32_t a, uint32_t b)
{
    int exp_a = exp_of(a), exp_b = exp_of(b), exp_diff = exp_a - exp_b, exp_z;
    uint32_t sig_a = frac_of(a), sig_b = frac_of(b), sign_z = sign_of(a), sig_z;
    if (!exp_diff) {
        if (!exp_a)
            return a + sig_b;                           /* both subnormal or zero */
        if (exp_a == 0xFF)
            return (sig_a | sig_b) ? F32_NAN : a;
        exp_z = exp_a;
        sig_z = 0x01000000 + sig_a + sig_b;
        if (!(sig_z & 1) && exp_z < 0xFE)
            return pack(sign_z, exp_z, sig_z >> 1);
        sig_z <<= 6;
    } else {
        sig_a <<= 6;
        sig_b <<= 6;
        if (exp_diff < 0) {
            if (exp_b == 0xFF)
                return sig_b ? F32_NAN : pack(sign_z, 0xFF, 0);
            exp_z = exp_b;
            sig_a += exp_a ? 0x20000000 : sig_a;
            sig_a = shift_right_jam32(sig_a, -exp_diff);
        } else {
            if (exp_a == 0xFF)
                return sig_a ? F32_NAN : a;
            exp_z = exp_a;
            sig_b += exp_b ? 0x20000000 : sig_b;
            sig_b = shift_right_jam32(sig_b, exp_diff);
        }
        sig_z = 0x20000000 + sig_a + sig_b;
        if (sig_z < 0x40000000) {
            exp_z--;
            sig_z <<= 1;
        }
    }
    return round_pack(sign_z, exp_z, sig_z);
}

static uint32_t sub_mags(uint32_t a, uint32_t b)
{
    int exp_a = exp_of(a), exp_b = exp_of(b), exp_diff = exp_a - exp_b, exp_z;
    uint32_t sig_a = frac_of(a), sig_b = frac_of(b), sign_z = sign_of(a), sig_x, sig_y;
    if (!exp_diff) {
        if (exp_a == 0xFF)
            return F32_NAN;                             /* NaN, or inf - inf */
        int32_t sig_diff = (int32_t)sig_a - (int32_t)sig_b;
        if (!sig_diff)
            return 0;                                   /* x - x = +0 */
        if (exp_a)
            exp_a--;
        if (sig_diff < 0) {
            sign_z ^= 1;
            sig_diff = -sig_diff;
        }
        int dist = clz32((uint32_t)sig_diff) - 8;
        exp_z = exp_a - dist;
        if (exp_z < 0) {
            dist = exp_a;
            exp_z = 0;
        }
        return pack(sign_z, exp_z, (uint32_t)sig_diff << dist);
    }
    sig_a <<= 7;
    sig_b <<= 7;
    if (exp_diff < 0) {
        sign_z ^= 1;
        if (exp_b == 0xFF)
            return sig_b ? F32_NAN : pack(sign_z, 0xFF, 0);
        exp_z = exp_b - 1;
        sig_x = sig_b | 0x40000000;
        sig_y = sig_a + (exp_a ? 0x40000000 : sig_a);
        exp_diff = -exp_diff;
    } else {
        if (exp_a == 0xFF)
            return sig_a ? F32_NAN : a;
        exp_z = exp_a - 1;
        sig_x = sig_a | 0x40000000;
        sig_y = sig_b + (exp_b ? 0x40000000 : sig_b);
    }
    return norm_round_pack(sign_z, exp_z, sig_x - shift_right_jam32(sig_y, exp_diff));
}

static uint32_t f32_add(uint32_t a, uint32_t b)
{
    return sign_of(a) == sign_of(b) ? add_mags(a, b) : sub_mags(a, b);
}

/* A subnormal's significand moved up so its hidden bit is at bit 23 */
static void norm_subnormal(uint32_t *sig, int *exp)
{
    int dist = clz32(*sig) - 8;
    *sig <<= dist;
    *exp = 1 - dist;
}

static uint32_t f32_mul(uint32_t a, uint32_t b)
{
    int exp_a = exp_of(a), exp_b = exp_of(b);
    uint32_t sig_a = frac_of(a), sig_b = frac_of(b), sign_z = sign_of(a) ^ sign_of(b);
    if (exp_a == 0xFF) {
        if (sig_a || (exp_b == 0xFF && sig_b))
            return F32_NAN;
        return (exp_b | sig_b) ? pack(sign_z, 0xFF, 0) : F32_NAN;   /* inf * 0 = NaN */
    }
    if (exp_b == 0xFF) {
        if (sig_b)
            return F32_NAN;
        return (exp_a | sig_a) ? pack(sign_z, 0xFF, 0) : F32_NAN;
    }
    if (!exp_a) {
        if (!sig_a)
            return pack(sign_z, 0, 0);
        norm_subnormal(&sig_a, &exp_a);
    }
    if (!exp_b) {
        if (!sig_b)
            return pack(sign_z, 0, 0);
        norm_subnormal(&sig_b, &exp_b);
    }
    int exp_z = exp_a + exp_b - 0x7F;
    sig_a = (sig_a | 0x00800000) << 7;
    sig_b = (sig_b | 0x00800000) << 8;
    uint64_t product = (uint64_t)sig_a * sig_b;                     /* multu */
    uint32_t sig_z = (uint32_t)(product >> 32) | ((uint32_t)product != 0);
    if (sig_z < 0x40000000) {
        exp_z--;
        sig_z <<= 1;
    }
    return round_pack(sign_z, exp_z, sig_z);
}

static uint32_t f32_div(uint32_t a, uint32_t b)
{
    int exp_a = exp_of(a), exp_b = exp_of(b);
    uint32_t sig_a = frac_of(a), sig_b = frac_of(b), sign_z = sign_of(a) ^ sign_of(b);
    if (exp_a == 0xFF) {
        if (sig_a || exp_b == 0xFF)
            return F32_NAN;                                         /* NaN, inf / inf */
        return pack(sign_z, 0xFF, 0);
    }
    if (exp_b == 0xFF)
        return sig_b ? F32_NAN : pack(sign_z, 0, 0);
    if (!exp_b) {
        if (!sig_b)
            return (exp_a | sig_a) ? pack(sign_z, 0xFF, 0) : F32_NAN;   /* x / 0, 0 / 0 */
        norm_subnormal(&sig_b, &exp_b);
    }
    if (!exp_a) {
        if (!sig_a)
            return pack(sign_z, 0, 0);
        norm_subnormal(&sig_a, &exp_a);
    }
    int exp_z = exp_a - exp_b + 0x7E;
    sig_a |= 0x00800000;
    sig_b |= 0x00800000;
    uint64_t sig64_a;
    if (sig_a < sig_b) {
        exp_z--;
        sig64_a = (uint64_t)sig_a << 31;
    } else {
        sig64_a = (uint64_t)sig_a << 30;
    }
    uint32_t sig_z = (uint32_t)(sig64_a / sig_b);                   /* libgcc __udivdi3: integer only */
    if (!(sig_z & 0x3F))
        sig_z |= ((uint64_t)sig_b * sig_z != sig64_a);
    return round_pack(sign_z, exp_z, sig_z);
}

/* ---- the helpers GCC calls ---- */

float SF(__addsf3)(float a, float b)
{
    f32 x = { a }, y = { b }, z;
    z.u = f32_add(x.u, y.u);
    return z.f;
}

float SF(__subsf3)(float a, float b)
{
    f32 x = { a }, y = { b }, z;
    z.u = f32_add(x.u, y.u ^ 0x80000000u);
    return z.f;
}

float SF(__mulsf3)(float a, float b)
{
    f32 x = { a }, y = { b }, z;
    z.u = f32_mul(x.u, y.u);
    return z.f;
}

float SF(__divsf3)(float a, float b)
{
    f32 x = { a }, y = { b }, z;
    z.u = f32_div(x.u, y.u);
    return z.f;
}

float SF(__floatsisf)(int32_t a)
{
    f32 z;
    uint32_t sign = a < 0;
    if (!(a & 0x7FFFFFFF))
        z.u = sign ? 0xCF000000u : 0;                   /* 0 or INT_MIN */
    else
        z.u = norm_round_pack(sign, 0x9C, sign ? -(uint32_t)a : (uint32_t)a);
    return z.f;
}

int32_t SF(__fixsfsi)(float a)                          /* toward zero, saturates */
{
    f32 x = { a };
    int exp = exp_of(x.u);
    uint32_t sig = frac_of(x.u), sign = sign_of(x.u);
    int dist = 0x9E - exp;
    if (dist >= 32)
        return 0;
    if (dist <= 0) {
        if (x.u == 0xCF000000u)
            return INT32_MIN;
        return (exp == 0xFF && sig) ? INT32_MAX : sign ? INT32_MIN : INT32_MAX;
    }
    uint32_t abs_z = ((sig | 0x00800000) << 8) >> dist;
    return sign ? -(int32_t)abs_z : (int32_t)abs_z;
}

double SF(__extendsfdf2)(float a)
{
    f32 x = { a };
    f64 z;
    uint64_t sign = (uint64_t)sign_of(x.u) << 63;
    int exp = exp_of(x.u);
    uint32_t frac = frac_of(x.u);
    if (exp == 0xFF) {
        z.u = sign | 0x7FF0000000000000ull | (frac ? 0x0008000000000000ull | (uint64_t)frac << 29 : 0);
    } else if (!exp) {
        if (!frac) {
            z.u = sign;
        } else {
            norm_subnormal(&frac, &exp);                /* frac now has its hidden bit */
            z.u = sign + ((uint64_t)(exp - 1 + 0x380) << 52) + ((uint64_t)frac << 29);
        }
    } else {
        z.u = sign | (uint64_t)(exp + 0x380) << 52 | (uint64_t)frac << 29;
    }
    return z.d;
}

/* < 0 when a < b; 0 when equal; > 0 when greater or a NaN is involved */
int SF(__ltdf2)(double a, double b)
{
    f64 x = { a }, y = { b };
    uint64_t abs_a = x.u & ~(1ull << 63), abs_b = y.u & ~(1ull << 63);
    if (abs_a > 0x7FF0000000000000ull || abs_b > 0x7FF0000000000000ull)
        return 1;
    if (!abs_a && !abs_b)
        return 0;                                       /* +0 == -0 */
    int sign_a = x.u >> 63, sign_b = y.u >> 63;
    if (sign_a != sign_b)
        return sign_a ? -1 : 1;
    if (x.u == y.u)
        return 0;
    return ((x.u < y.u) ^ sign_a) ? -1 : 1;
}
