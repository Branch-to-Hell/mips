/* Minimal C library for our MIPS (TC-10): stdio.h
   Formatting is complete enough for Doom: %d %i %u %x %X %o %c %s %p %%, flags - 0 + space #,
   width and precision (also *), length h, l, z. %f/%e/%g print "?" (no floating point).
   Output (printf, puts, putchar, fprintf to stdout/stderr) goes through __putchar, which
   does nothing by default: "printf to nothing". A program can define its own
   void __putchar(int c) to send the characters somewhere (it replaces the default).
   Files: no file system. A program registers read-only files in memory with __mem_file_add
   (e.g. the WAD in the SDRAM) and reads them with fopen(name, "rb"), fread, fseek, ftell.
   sscanf reads integers (%d %i %u %x %o), %s, %c and %n. */
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

int __mem_file_add(const char *name, const void *data, long size);   /* 0, or -1 if full (4 files) */
FILE *fopen(const char *path, const char *mode);    /* read only, registered names only */
int fclose(FILE *f);
size_t fread(void *buf, size_t size, size_t count, FILE *f);
size_t fwrite(const void *buf, size_t size, size_t count, FILE *f);   /* stdout/stderr only */
int fseek(FILE *f, long offset, int whence);
long ftell(FILE *f);
int feof(FILE *f);
int remove(const char *path);                       /* always -1: no file system */
int rename(const char *from, const char *to);       /* always -1 */

int sscanf(const char *str, const char *fmt, ...);
int vsscanf(const char *str, const char *fmt, va_list ap);

#endif
