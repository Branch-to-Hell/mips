/* Minimal C library for our MIPS (TC-10): printf family and character output.
   One formatter (format below) writes through a small "sink": a buffer for snprintf, or
   __putchar for printf. __putchar does nothing unless the program defines its own. */
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <errno.h>

struct __file { int unused; };
static struct __file files[3];
FILE *const stdin = &files[0], *const stdout = &files[1], *const stderr = &files[2];

/* Weak: a program's own void __putchar(int c) replaces it (MMIO, a trace, ...) */
__attribute__((weak)) void __putchar(int c)
{
    (void)c;
}

typedef struct {
    char *buf;          /* NULL = send to __putchar */
    size_t size;        /* buffer size, terminator included */
    size_t count;       /* characters produced (also those that didn't fit) */
} sink;

static void emit(sink *out, char c)
{
    if (!out->buf)
        __putchar((unsigned char)c);
    else if (out->count + 1 < out->size)
        out->buf[out->count] = c;
    out->count++;
}

static void emit_repeat(sink *out, char c, int n)
{
    while (n-- > 0)
        emit(out, c);
}

/* Digits of value in base 8, 10 or 16, least significant first. Returns how many. */
static int to_digits(char *digits, unsigned long value, unsigned base, int upper)
{
    const char *set = upper ? "0123456789ABCDEF" : "0123456789abcdef";
    int n = 0;
    do {
        digits[n++] = set[value % base];
        value /= base;
    } while (value);
    return n;
}

static int format(sink *out, const char *fmt, va_list ap)
{
    for (; *fmt; fmt++) {
        if (*fmt != '%') {
            emit(out, *fmt);
            continue;
        }
        const char *spec_start = fmt;

        /* flags */
        int left = 0, zero = 0, plus = 0, space = 0, alt = 0;
        for (;; fmt++) {
            char f = fmt[1];
            if (f == '-') left = 1;
            else if (f == '0') zero = 1;
            else if (f == '+') plus = 1;
            else if (f == ' ') space = 1;
            else if (f == '#') alt = 1;
            else break;
        }
        fmt++;

        /* width and precision */
        int width = 0, precision = -1;
        if (*fmt == '*') {
            width = va_arg(ap, int);
            if (width < 0) {
                left = 1;
                width = -width;
            }
            fmt++;
        } else {
            while (*fmt >= '0' && *fmt <= '9')
                width = width * 10 + (*fmt++ - '0');
        }
        if (*fmt == '.') {
            fmt++;
            precision = 0;
            if (*fmt == '*') {
                precision = va_arg(ap, int);
                fmt++;
            } else {
                while (*fmt >= '0' && *fmt <= '9')
                    precision = precision * 10 + (*fmt++ - '0');
            }
        }

        /* length: int and long are both 32 bits here; ll is not supported */
        while (*fmt == 'h' || *fmt == 'l' || *fmt == 'z' || *fmt == 't')
            fmt++;

        char conv = *fmt;
        if (!conv)
            break;

        char digits[24];
        const char *text = digits;
        int len = 0;
        const char *prefix = "";
        int numeric = 1;

        switch (conv) {
        case 'd':
        case 'i': {
            long v = va_arg(ap, long);
            unsigned long m = v < 0 ? 0 - (unsigned long)v : (unsigned long)v;
            len = to_digits(digits, m, 10, 0);
            prefix = v < 0 ? "-" : plus ? "+" : space ? " " : "";
            break;
        }
        case 'u':
            len = to_digits(digits, va_arg(ap, unsigned long), 10, 0);
            break;
        case 'x':
        case 'X': {
            unsigned long v = va_arg(ap, unsigned long);
            len = to_digits(digits, v, 16, conv == 'X');
            if (alt && v) prefix = conv == 'X' ? "0X" : "0x";
            break;
        }
        case 'o':
            len = to_digits(digits, va_arg(ap, unsigned long), 8, 0);
            if (alt) prefix = "0";
            break;
        case 'p':
            len = to_digits(digits, (uintptr_t)va_arg(ap, void *), 16, 0);
            prefix = "0x";
            break;
        case 'c':
            digits[0] = (char)va_arg(ap, int);
            len = 1;
            numeric = 0;
            break;
        case 's':
            text = va_arg(ap, const char *);
            if (!text) text = "(null)";
            len = precision >= 0 ? (int)strnlen(text, precision) : (int)strlen(text);
            numeric = 0;
            break;
        case 'f': case 'F': case 'e': case 'E': case 'g': case 'G':
            (void)va_arg(ap, double);           /* no floating point: keep the arguments in step */
            text = "?";
            len = 1;
            numeric = 0;
            break;
        case '%':
            emit(out, '%');
            continue;
        default:                                /* unknown: print it as it was written */
            for (; spec_start <= fmt; spec_start++)
                emit(out, *spec_start);
            continue;
        }

        if (!numeric) {
            if (!left) emit_repeat(out, ' ', width - len);
            for (int i = 0; i < len; i++) emit(out, text[i]);
            if (left) emit_repeat(out, ' ', width - len);
            continue;
        }

        /* number: [spaces][prefix][zeros]digits[spaces] */
        if (precision == 0 && len == 1 && digits[0] == '0')
            len = 0;                            /* printf("%.0d", 0) prints nothing */
        int zeros = precision > len ? precision - len : 0;
        int prefix_len = strlen(prefix);
        int pad = width - prefix_len - zeros - len;
        if (zero && !left && precision < 0) {
            zeros += pad > 0 ? pad : 0;
            pad = 0;
        }
        if (!left) emit_repeat(out, ' ', pad);
        for (const char *p = prefix; *p; p++) emit(out, *p);
        emit_repeat(out, '0', zeros);
        while (len > 0) emit(out, digits[--len]);
        if (left) emit_repeat(out, ' ', pad);
    }
    return (int)out->count;
}

int vsnprintf(char *buf, size_t size, const char *fmt, va_list ap)
{
    sink out = { buf ? buf : (char *)"", buf ? size : 0, 0 };
    format(&out, fmt, ap);
    if (buf && size)
        buf[out.count < size ? out.count : size - 1] = '\0';
    return (int)out.count;
}

int snprintf(char *buf, size_t size, const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(buf, size, fmt, ap);
    va_end(ap);
    return n;
}

int vsprintf(char *buf, const char *fmt, va_list ap)
{
    return vsnprintf(buf, SIZE_MAX, fmt, ap);
}

int sprintf(char *buf, const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    int n = vsprintf(buf, fmt, ap);
    va_end(ap);
    return n;
}

int vprintf(const char *fmt, va_list ap)
{
    sink out = { NULL, 0, 0 };
    return format(&out, fmt, ap);
}

int printf(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    int n = vprintf(fmt, ap);
    va_end(ap);
    return n;
}

int vfprintf(FILE *f, const char *fmt, va_list ap)
{
    (void)f;                                    /* stdout and stderr both go to __putchar */
    return vprintf(fmt, ap);
}

int fprintf(FILE *f, const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    int n = vfprintf(f, fmt, ap);
    va_end(ap);
    return n;
}

int putchar(int c)
{
    __putchar((unsigned char)c);
    return (unsigned char)c;
}

int fputc(int c, FILE *f) { (void)f; return putchar(c); }
int putc(int c, FILE *f)  { return fputc(c, f); }

int fputs(const char *s, FILE *f)
{
    (void)f;
    while (*s)
        putchar(*s++);
    return 0;
}

int puts(const char *s)
{
    fputs(s, stdout);
    putchar('\n');
    return 0;
}

int fflush(FILE *f) { (void)f; return 0; }

/* No file system yet */
FILE *fopen(const char *path, const char *mode)
{
    (void)path;
    (void)mode;
    errno = ENOENT;
    return NULL;
}

int fclose(FILE *f) { (void)f; return EOF; }

size_t fread(void *buf, size_t size, size_t count, FILE *f)
{
    (void)buf; (void)size; (void)count; (void)f;
    return 0;
}

size_t fwrite(const void *buf, size_t size, size_t count, FILE *f)
{
    if (f == stdout || f == stderr) {
        const char *p = buf;
        for (size_t i = 0; i < size * count; i++)
            putchar(p[i]);
        return count;
    }
    return 0;
}
