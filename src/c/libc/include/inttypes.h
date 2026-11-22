/* Minimal C library for our MIPS (TC-10): inttypes.h (format macros; int is 32 bits, long long 64) */
#ifndef _INTTYPES_H
#define _INTTYPES_H

#include <stdint.h>

#define PRId8  "d"
#define PRId16 "d"
#define PRId32 "d"
#define PRIi32 "i"
#define PRIu8  "u"
#define PRIu16 "u"
#define PRIu32 "u"
#define PRIx32 "x"
#define PRIX32 "X"
/* 64-bit: printf has no %ll (stdio.h), they print as "?" */
#define PRId64 "lld"
#define PRIi64 "lli"
#define PRIu64 "llu"
#define PRIx64 "llx"

#endif
