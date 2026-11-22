/* Minimal C library for our MIPS (TC-10): errno.h */
#ifndef _ERRNO_H
#define _ERRNO_H

extern int errno;

#define ENOENT 2
#define EIO    5
#define EBADF  9
#define EEXIST 17
#define EISDIR 21
#define ENOMEM 12
#define EINVAL 22
#define ERANGE 34

#endif
