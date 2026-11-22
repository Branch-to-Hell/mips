/* Minimal C library for our MIPS (TC-10): assert.h. A failed assert calls abort(). */
#ifndef _ASSERT_H
#define _ASSERT_H

#include <stdlib.h>

#ifdef NDEBUG
#define assert(x) ((void)0)
#else
#define assert(x) ((x) ? (void)0 : abort())
#endif

#endif
