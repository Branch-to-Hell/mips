/* Minimal C library for our MIPS (TC-10): limits.h, from GCC's predefined macros
   (GCC's own limits.h wants a system one under it with #include_next). */
#ifndef _LIMITS_H
#define _LIMITS_H

#define CHAR_BIT   8
#define SCHAR_MIN  (-SCHAR_MAX - 1)
#define SCHAR_MAX  __SCHAR_MAX__
#define UCHAR_MAX  (SCHAR_MAX * 2 + 1)
#ifdef __CHAR_UNSIGNED__
#define CHAR_MIN   0
#define CHAR_MAX   UCHAR_MAX
#else
#define CHAR_MIN   SCHAR_MIN
#define CHAR_MAX   SCHAR_MAX
#endif
#define SHRT_MIN   (-SHRT_MAX - 1)
#define SHRT_MAX   __SHRT_MAX__
#define USHRT_MAX  (SHRT_MAX * 2 + 1)
#define INT_MIN    (-INT_MAX - 1)
#define INT_MAX    __INT_MAX__
#define UINT_MAX   (INT_MAX * 2U + 1U)
#define LONG_MIN   (-LONG_MAX - 1L)
#define LONG_MAX   __LONG_MAX__
#define ULONG_MAX  (LONG_MAX * 2UL + 1UL)
#define LLONG_MIN  (-LLONG_MAX - 1LL)
#define LLONG_MAX  __LONG_LONG_MAX__
#define ULLONG_MAX (LLONG_MAX * 2ULL + 1ULL)
#define PATH_MAX   256

#endif
