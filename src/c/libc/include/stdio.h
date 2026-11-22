/* Minimal C library for our MIPS (TC-10): stdio.h
   Formatting is complete enough for Doom: %d %i %u %x %X %o %c %s %p %%, flags - 0 + space #,
   width and precision (also *), length h, l, z. %f/%e/%g print "?" (no floating point).
   Output (printf, puts, putchar, fprintf to stdout/stderr) goes through __putchar, which
   does nothing by default: "printf to nothing". A program can define its own
   void __putchar(int c) to send the characters somewhere (it replaces the default).
   No files yet: fopen returns NULL (the WAD comes from SDRAM, DOOM tasks). */
#ifndef _STDIO_H
#define _STDIO_H

#include <stddef.h>
#include <stdarg.h>

#define EOF (-1)
#define BUFSIZ 256
#define SEEK_SET 0
#define SEEK_CUR 1
#define SEEK_END 2

typedef struct __file FILE;
extern FILE *const stdin, *const stdout, *const stderr;

void __putchar(int c);

int printf(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
int vprintf(const char *fmt, va_list ap);
int fprintf(FILE *f, const char *fmt, ...) __attribute__((format(printf, 2, 3)));
int vfprintf(FILE *f, const char *fmt, va_list ap);
int sprintf(char *buf, const char *fmt, ...) __attribute__((format(printf, 2, 3)));
int vsprintf(char *buf, const char *fmt, va_list ap);
int snprintf(char *buf, size_t size, const char *fmt, ...) __attribute__((format(printf, 3, 4)));
int vsnprintf(char *buf, size_t size, const char *fmt, va_list ap);

int putchar(int c);
int puts(const char *s);
int fputc(int c, FILE *f);
int putc(int c, FILE *f);
int fputs(const char *s, FILE *f);
int fflush(FILE *f);

FILE *fopen(const char *path, const char *mode);    /* always NULL for now */
int fclose(FILE *f);
size_t fread(void *buf, size_t size, size_t count, FILE *f);
size_t fwrite(const void *buf, size_t size, size_t count, FILE *f);

#endif
