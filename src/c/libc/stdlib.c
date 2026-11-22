/* Minimal C library for our MIPS (TC-10): the rest of stdlib.h, ctype.h and errno. */
#include <stdlib.h>
#include <ctype.h>
#include <errno.h>
#include <limits.h>

int errno;

/* ---- ctype (ASCII) ---- */
int isdigit(int c)  { return c >= '0' && c <= '9'; }
int isupper(int c)  { return c >= 'A' && c <= 'Z'; }
int islower(int c)  { return c >= 'a' && c <= 'z'; }
int isalpha(int c)  { return isupper(c) || islower(c); }
int isalnum(int c)  { return isalpha(c) || isdigit(c); }
int isxdigit(int c) { return isdigit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'); }
int isspace(int c)  { return c == ' ' || (c >= '\t' && c <= '\r'); }
int isprint(int c)  { return c >= ' ' && c <= '~'; }
int iscntrl(int c)  { return (c >= 0 && c < ' ') || c == 127; }
int ispunct(int c)  { return isprint(c) && c != ' ' && !isalnum(c); }
int toupper(int c)  { return islower(c) ? c - 'a' + 'A' : c; }
int tolower(int c)  { return isupper(c) ? c - 'A' + 'a' : c; }

/* ---- numbers ---- */
int abs(int x)    { return x < 0 ? -x : x; }
long labs(long x) { return x < 0 ? -x : x; }

static int digit_value(int c)
{
    if (isdigit(c)) return c - '0';
    if (islower(c)) return c - 'a' + 10;
    if (isupper(c)) return c - 'A' + 10;
    return 99;
}

/* Parses [spaces][+|-][0x|0]digits. Returns the magnitude; *negative says the sign.
   Saturates at max_magnitude with errno = ERANGE. */
static unsigned long parse(const char *s, char **end, int base, int *negative,
                           unsigned long max_magnitude)
{
    const char *p = s;
    unsigned long value = 0;
    int any = 0, overflow = 0;

    while (isspace((unsigned char)*p))
        p++;
    *negative = 0;
    if (*p == '+' || *p == '-')
        *negative = (*p++ == '-');
    if ((base == 0 || base == 16) && p[0] == '0' && (p[1] == 'x' || p[1] == 'X') &&
        isxdigit((unsigned char)p[2])) {
        p += 2;
        base = 16;
    } else if (base == 0) {
        base = (*p == '0') ? 8 : 10;
    }
    for (int d; (d = digit_value((unsigned char)*p)) < base; p++) {
        any = 1;
        if (value > (max_magnitude - d) / base)
            overflow = 1;
        else
            value = value * base + d;
    }
    if (end)
        *end = (char *)(any ? p : s);
    if (overflow) {
        errno = ERANGE;
        value = max_magnitude;
    }
    return value;
}

long strtol(const char *s, char **end, int base)
{
    int negative;
    unsigned long m = parse(s, end, base, &negative, (unsigned long)LONG_MAX + 1);
    if (!negative && m > LONG_MAX) {
        errno = ERANGE;
        return LONG_MAX;
    }
    return negative ? (long)(0 - m) : (long)m;
}

unsigned long strtoul(const char *s, char **end, int base)
{
    int negative;
    unsigned long m = parse(s, end, base, &negative, ULONG_MAX);
    return negative ? 0 - m : m;
}

int atoi(const char *s)  { return (int)strtol(s, NULL, 10); }
long atol(const char *s) { return strtol(s, NULL, 10); }

/* ---- rand: xorshift (no multiply), 15-bit results like most C libraries ---- */
static unsigned rand_state = 1;

void srand(unsigned seed) { rand_state = seed ? seed : 1; }

int rand(void)
{
    unsigned x = rand_state;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    rand_state = x;
    return (int)(x & RAND_MAX);
}

/* ---- qsort: Shell sort (no recursion, no extra memory) ---- */
static void swap_bytes(char *a, char *b, size_t size)
{
    while (size--) {
        char t = *a;
        *a++ = *b;
        *b++ = t;
    }
}

void qsort(void *base, size_t count, size_t size, int (*compare)(const void *, const void *))
{
    char *a = base;
    for (size_t gap = count / 2; gap > 0; gap /= 2)
        for (size_t i = gap; i < count; i++)
            for (size_t j = i; j >= gap && compare(a + (j - gap) * size, a + j * size) > 0; j -= gap)
                swap_bytes(a + (j - gap) * size, a + j * size, size);
}

/* ---- program end: like main returning in crt0.S, $v0 = status and a self-jump ---- */
void exit(int status)
{
    __asm__ volatile(
        "move  $v0, %0\n"
        "1:    j 1b\n"
        "      nop\n" : : "r"(status) : "v0");
    __builtin_unreachable();
}

void abort(void)
{
    exit(134);                  /* 128 + SIGABRT, like a shell shows it */
}

char *getenv(const char *name)
{
    (void)name;
    return NULL;
}
