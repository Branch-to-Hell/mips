/* Minimal C library for our MIPS (TC-10): fcntl.h (the flags only; there is no open()) */
#ifndef _FCNTL_H
#define _FCNTL_H

#include <sys/types.h>

#define O_RDONLY 0
#define O_WRONLY 1
#define O_RDWR   2
#define O_CREAT  0100
#define O_TRUNC  01000

#endif
