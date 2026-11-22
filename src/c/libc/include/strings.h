/* Minimal C library for our MIPS (TC-10): strings.h */
#ifndef _STRINGS_H
#define _STRINGS_H

#include <stddef.h>

int strcasecmp(const char *a, const char *b);
int strncasecmp(const char *a, const char *b, size_t n);

#endif
