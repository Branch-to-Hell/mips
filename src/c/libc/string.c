/* Minimal C library for our MIPS (TC-10): string.h and strings.h.
   memcpy/memmove/memset move whole words (lw/sw) when the pointers allow it and bytes
   (lbu/sb) otherwise. MIPS I has lwl/lwr for unaligned words, but our CPU doesn't. */
#include <string.h>
#include <strings.h>
#include <stdint.h>
#include <stdlib.h>
#include <ctype.h>

#define WORD_ALIGNED(p) (((uintptr_t)(p) & 3) == 0)

void *memcpy(void *dst, const void *src, size_t n)
{
    unsigned char *d = dst;
    const unsigned char *s = src;
    if (WORD_ALIGNED(d) && WORD_ALIGNED(s)) {
        uint32_t *dw = (uint32_t *)d;
        const uint32_t *sw = (const uint32_t *)s;
        for (; n >= 16; n -= 16) {          /* 4 words per loop */
            dw[0] = sw[0]; dw[1] = sw[1]; dw[2] = sw[2]; dw[3] = sw[3];
            dw += 4; sw += 4;
        }
        for (; n >= 4; n -= 4)
            *dw++ = *sw++;
        d = (unsigned char *)dw;
        s = (const unsigned char *)sw;
    }
    while (n--)
        *d++ = *s++;
    return dst;
}

void *memmove(void *dst, const void *src, size_t n)
{
    unsigned char *d = dst;
    const unsigned char *s = src;
    if (d <= s || d >= s + n)               /* no overlap that a forward copy would break */
        return memcpy(dst, src, n);
    d += n;                                 /* copy backwards */
    s += n;
    if (WORD_ALIGNED(d) && WORD_ALIGNED(s)) {
        for (; n >= 4; n -= 4) {
            d -= 4; s -= 4;
            *(uint32_t *)d = *(const uint32_t *)s;
        }
    }
    while (n--)
        *--d = *--s;
    return dst;
}

void *memset(void *dst, int c, size_t n)
{
    unsigned char *d = dst;
    unsigned char b = (unsigned char)c;
    while (n && !WORD_ALIGNED(d)) {
        *d++ = b;
        n--;
    }
    uint32_t w = b * 0x01010101u;           /* shifts + adds, no mult */
    uint32_t *dw = (uint32_t *)d;
    for (; n >= 16; n -= 16) {
        dw[0] = w; dw[1] = w; dw[2] = w; dw[3] = w;
        dw += 4;
    }
    for (; n >= 4; n -= 4)
        *dw++ = w;
    d = (unsigned char *)dw;
    while (n--)
        *d++ = b;
    return dst;
}

int memcmp(const void *a, const void *b, size_t n)
{
    const unsigned char *x = a, *y = b;
    for (; n; n--, x++, y++)
        if (*x != *y)
            return *x - *y;
    return 0;
}

void *memchr(const void *s, int c, size_t n)
{
    const unsigned char *p = s;
    for (; n; n--, p++)
        if (*p == (unsigned char)c)
            return (void *)p;
    return NULL;
}

size_t strlen(const char *s)
{
    const char *p = s;
    while (*p)
        p++;
    return p - s;
}

size_t strnlen(const char *s, size_t max)
{
    size_t n = 0;
    while (n < max && s[n])
        n++;
    return n;
}

char *strcpy(char *dst, const char *src)
{
    char *d = dst;
    while ((*d++ = *src++))
        ;
    return dst;
}

char *strncpy(char *dst, const char *src, size_t n)
{
    size_t i = 0;
    for (; i < n && src[i]; i++)
        dst[i] = src[i];
    for (; i < n; i++)                      /* the standard pads with zeros */
        dst[i] = '\0';
    return dst;
}

char *strcat(char *dst, const char *src)
{
    strcpy(dst + strlen(dst), src);
    return dst;
}

char *strncat(char *dst, const char *src, size_t n)
{
    char *d = dst + strlen(dst);
    for (; n && *src; n--)
        *d++ = *src++;
    *d = '\0';
    return dst;
}

int strcmp(const char *a, const char *b)
{
    while (*a && *a == *b) {
        a++;
        b++;
    }
    return (unsigned char)*a - (unsigned char)*b;
}

int strncmp(const char *a, const char *b, size_t n)
{
    for (; n; n--, a++, b++) {
        if (*a != *b)
            return (unsigned char)*a - (unsigned char)*b;
        if (!*a)
            break;
    }
    return 0;
}

int strcasecmp(const char *a, const char *b)
{
    int x, y;
    do {
        x = tolower((unsigned char)*a++);
        y = tolower((unsigned char)*b++);
    } while (x && x == y);
    return x - y;
}

int strncasecmp(const char *a, const char *b, size_t n)
{
    int x = 0, y = 0;
    for (; n; n--) {
        x = tolower((unsigned char)*a++);
        y = tolower((unsigned char)*b++);
        if (!x || x != y)
            break;
    }
    return n ? x - y : 0;
}

char *strchr(const char *s, int c)
{
    for (;; s++) {
        if (*s == (char)c)
            return (char *)s;
        if (!*s)
            return NULL;
    }
}

char *strrchr(const char *s, int c)
{
    const char *last = NULL;
    for (;; s++) {
        if (*s == (char)c)
            last = s;
        if (!*s)
            return (char *)last;
    }
}

char *strstr(const char *haystack, const char *needle)
{
    size_t n = strlen(needle);
    for (; *haystack; haystack++)
        if (!strncmp(haystack, needle, n))
            return (char *)haystack;
    return n ? NULL : (char *)haystack;
}

char *strdup(const char *s)
{
    size_t n = strlen(s) + 1;
    char *copy = malloc(n);
    return copy ? memcpy(copy, s, n) : NULL;
}

char *strerror(int errnum)
{
    (void)errnum;
    return "error";
}
