/* Minimal C library for our MIPS (TC-10): stdlib.h */
#ifndef _STDLIB_H
#define _STDLIB_H

#include <stddef.h>

#define EXIT_SUCCESS 0
#define EXIT_FAILURE 1
#define RAND_MAX 0x7FFF

void *malloc(size_t size);
void free(void *ptr);
void *calloc(size_t count, size_t size);
void *realloc(void *ptr, size_t size);

int atoi(const char *s);
long atol(const char *s);
long strtol(const char *s, char **end, int base);
unsigned long strtoul(const char *s, char **end, int base);
int abs(int x);
long labs(long x);

int rand(void);
void srand(unsigned seed);

void qsort(void *base, size_t count, size_t size, int (*compare)(const void *, const void *));

/* No OS: exit and abort stop the CPU on a self-jump, like main returning (crt0.S). */
void exit(int status) __attribute__((noreturn));
void abort(void) __attribute__((noreturn));
char *getenv(const char *name);     /* always NULL */

#endif
