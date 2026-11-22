/* TC-10: tests of the minimal C library (src/c/libc).
   Each check has a number. At the end:
     all pass  -> LEDR = 0x3FF, HEX = 0x00600D, main returns 0 (the pass protocol of the other tests)
     a failure -> HEX = 0xBAD000 + number of the first failed check, main returns that number
   Needs the phase 2 ISA (lbu/sb, divu, sltu...): runs in ref_sim.py now, and on the CPU
   (Verilator, board) once CPU-7 and CPU-8 are in. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <ctype.h>
#include <unistd.h>

#define LEDR (*(volatile unsigned *)0xFFFF0018)
#define HEX  (*(volatile unsigned *)0xFFFF001C)

static int checks, first_failure;

static void check(int number, int ok)
{
    checks++;
    if (!ok && !first_failure)
        first_failure = number;
}

/* printf goes to __putchar. The library's one does nothing ("printf to nothing");
   this test defines its own to see what printf sends. */
static char console[128];
static int console_len;

void __putchar(int c)
{
    if (console_len < (int)sizeof console - 1)
        console[console_len++] = (char)c;
}

static int bytes_are(const unsigned char *p, int n, int (*expected)(int))
{
    for (int i = 0; i < n; i++)
        if (p[i] != (unsigned char)expected(i))
            return 0;
    return 1;
}

static int pattern(int i) { return (i * 7 + 3) & 0xFF; }

static unsigned char src[96], dst[96];

static void test_memory(void)
{
    for (int i = 0; i < 96; i++) src[i] = (unsigned char)pattern(i);

    /* memcpy: aligned (word path) and every misalignment (byte path), with odd lengths */
    for (int off_d = 0; off_d < 4; off_d++)
        for (int off_s = 0; off_s < 4; off_s++) {
            memset(dst, 0xEE, sizeof dst);
            void *r = memcpy(dst + off_d, src + off_s, 37);
            int ok = r == dst + off_d && dst[off_d + 37] == 0xEE && (off_d == 0 || dst[off_d - 1] == 0xEE);
            for (int i = 0; i < 37; i++)
                ok &= dst[off_d + i] == src[off_s + i];
            check(1, ok);
        }

    /* memmove with overlap, both directions */
    memcpy(dst, src, 96);
    memmove(dst + 8, dst, 64);                      /* forward overlap: must copy backwards */
    check(2, !memcmp(dst + 8, src, 64) && !memcmp(dst, src, 8));
    memcpy(dst, src, 96);
    memmove(dst + 1, dst + 6, 50);                  /* backward overlap, unaligned */
    check(3, !memcmp(dst + 1, src + 6, 50));

    /* memset at odd addresses and lengths */
    memset(dst, 0, 96);
    memset(dst + 3, 0x5A, 41);
    check(4, dst[2] == 0 && dst[3] == 0x5A && dst[43] == 0x5A && dst[44] == 0);

    check(5, memcmp("abc", "abd", 3) < 0 && memcmp("abd", "abc", 3) > 0 && memcmp("ab", "ab", 2) == 0);
    check(6, bytes_are(src, 96, pattern));          /* the source was never touched */
}

static void test_strings(void)
{
    char buf[32];
    check(10, strlen("") == 0 && strlen("doom") == 4);
    check(11, !strcmp(strcpy(buf, "E1M1"), "E1M1") && strcmp("a", "b") < 0 && strcmp("b", "a") > 0);
    check(12, !strcmp(strcat(buf, "!"), "E1M1!"));
    check(13, !strncmp("DOOM2", "DOOMX", 4) && strncmp("DOOM2", "DOOMX", 5) != 0);
    check(14, !strcasecmp("Doom.WAD", "DOOM.wad") && strncasecmp("abcx", "ABCY", 4) < 0);
    const char *map = "e1m1";
    check(15, strchr(map, 'm') == map + 2 && strchr(map, 'x') == NULL && strchr(map, 0) == map + 4);
    check(16, strrchr("a/b/c", '/') && !strcmp(strrchr("a/b/c", '/'), "/c"));
    check(17, strstr("doom.wad", ".wad") && !strcmp(strstr("doom.wad", ".wad"), ".wad") && !strstr("doom", "x"));
    memset(buf, 'x', sizeof buf);
    strncpy(buf, "ab", 5);
    check(18, buf[0] == 'a' && buf[2] == 0 && buf[4] == 0 && buf[5] == 'x');
    check(19, toupper('q') == 'Q' && tolower('Q') == 'q' && isdigit('7') && !isalpha('7') && isspace('\t'));
    char *end;
    check(20, atoi("  -42") == -42 && strtol("0x1F", &end, 0) == 31 && *end == 0);
    check(21, strtol("077", NULL, 0) == 63 && strtoul("4294967295", NULL, 10) == 4294967295u);
    check(22, strtol("12abc", &end, 10) == 12 && !strcmp(end, "abc"));
}

static void test_printf(void)
{
    char buf[64];
    snprintf(buf, sizeof buf, "%d|%5d|%-5d|%05d|%+d", -7, 42, 42, 42, 3);
    check(30, !strcmp(buf, "-7|   42|42   |00042|+3"));
    snprintf(buf, sizeof buf, "%x|%X|%08x|%#x|%o|%u", 0xBEEF, 0xBEEF, 0x1234, 255, 8, 4000000000u);
    check(31, !strcmp(buf, "beef|BEEF|00001234|0xff|10|4000000000"));
    snprintf(buf, sizeof buf, "%s|%-6s|%6s|%.2s|%c|%%", "doom", "ab", "ab", "xyz", 'Z');
    check(32, !strcmp(buf, "doom|ab    |    ab|xy|Z|%"));
    snprintf(buf, sizeof buf, "%*d|%.3d|%d|%d", 4, 7, 5, 0, -2147483647 - 1);
    check(33, !strcmp(buf, "   7|005|0|-2147483648"));
    snprintf(buf, sizeof buf, "%p|%s", (void *)0x10010000, (char *)NULL);
    check(34, !strcmp(buf, "0x10010000|(null)"));

    /* Truncation: returns the full length, writes size - 1 characters and the terminator */
    int n = snprintf(buf, 6, "STBAR%d", 123);
    check(35, n == 8 && !strcmp(buf, "STBAR"));
    check(36, snprintf(NULL, 0, "%d", 12345) == 5);
    check(37, sprintf(buf, "W%dH%d", 320, 200) == 8 && !strcmp(buf, "W320H200"));

    /* printf: through __putchar, returns the number of characters */
    console_len = 0;
    n = printf("E%dM%d: %s\n", 1, 1, "Hangar");
    puts("ok");
    console[console_len] = 0;
    check(38, n == 13 && !strcmp(console, "E1M1: Hangar\nok\n"));
    fprintf(stderr, "%d", 9);
    check(39, console[console_len - 1] == '9');
    check(40, fopen("doom1.wad", "rb") == NULL);
}

static int aligned8(void *p) { return ((uintptr_t)p & 7) == 0; }

static void test_malloc(void)
{
    char *a = malloc(10), *b = malloc(100), *c = malloc(1000);
    check(50, a && b && c && aligned8(a) && aligned8(b) && aligned8(c));
    check(51, a + 10 <= b && b + 100 <= c);         /* no overlap */
    memset(a, 'a', 10);
    memset(b, 'b', 100);
    memset(c, 'c', 1000);
    check(52, a[9] == 'a' && b[0] == 'b' && b[99] == 'b' && c[0] == 'c');

    /* free and reuse: a smaller block goes where b was */
    free(b);
    char *d = malloc(40);
    check(53, d == b && a[9] == 'a' && c[0] == 'c');

    /* realloc keeps the contents when it moves */
    memcpy(d, "0123456789", 10);
    char *e = realloc(d, 3000);
    check(54, e && !memcmp(e, "0123456789", 10) && aligned8(e));

    /* calloc returns zeros even on memory that was dirty */
    memset(c, 0xFF, 1000);
    free(c);
    unsigned *z = calloc(250, 4);
    int zeros = z != NULL;
    for (int i = 0; zeros && i < 250; i++)
        zeros = z[i] == 0;
    check(55, zeros);

    /* strdup */
    char *s = strdup("doomguy");
    check(56, s && !strcmp(s, "doomguy"));

    /* too big: NULL, and the heap still works */
    check(57, malloc(1 << 20) == NULL && malloc(0) == NULL);

    /* free everything: the free blocks join, so one big block fits again */
    free(a); free(e); free(z); free(s);
    char *big = malloc(8000);
    check(58, big != NULL);
    memset(big, 0x11, 8000);
    free(big);

    /* sbrk: the heap ends at the end of the data region */
    char *top = sbrk(0);
    check(59, top <= (char *)0x10014000 && sbrk(0x10000) == (void *)-1);

    /* fill the heap with small blocks, then free them all */
    int count = 0;
    void *blocks[400];
    while (count < 400 && (blocks[count] = malloc(24)) != NULL)
        count++;
    check(60, count > 100);                        /* about 12 KB of heap / 32 bytes */
    for (int i = 0; i < count; i++)
        free(blocks[i]);
    check(61, malloc(4000) != NULL);
}

static void test_realloc_in_place(void)
{
    /* grows into the free block right after it, without moving */
    char *x = malloc(16), *y = malloc(16), *z = malloc(16);
    memcpy(x, "abcdefghijklmno", 16);
    free(y);
    char *x2 = realloc(x, 24);
    check(70, x2 == x && !memcmp(x2, "abcdefghijklmno", 16));
    /* x2's new bytes 16..23 are where y's header was. Fill them with data that looks like
       a free header (size 24, free): if malloc still believed y existed, it would take it
       and write over them. */
    unsigned *tail = (unsigned *)(x2 + 16);
    tail[0] = 24;
    tail[1] = 0;
    char *w = malloc(16);
    check(71, w && (w >= x2 + 24 || w + 16 <= x2) && (w >= z + 16 || w + 16 <= z));
    memset(w, 'w', 16);
    check(72, !memcmp(x2, "abcdefghijklmno", 16) && tail[0] == 24 && tail[1] == 0);
    /* shrinks in place */
    check(73, realloc(x2, 8) == x2 && !memcmp(x2, "abcdefgh", 8));
    free(x2); free(z); free(w);
    check(74, realloc(NULL, 10) != NULL);
}

int main(void)
{
    test_memory();
    test_strings();
    test_printf();
    test_malloc();
    test_realloc_in_place();

    if (first_failure) {
        HEX = 0xBAD000 | first_failure;
        return first_failure;
    }
    LEDR = 0x3FF;
    HEX = 0x00600D;
    return 0;
}
