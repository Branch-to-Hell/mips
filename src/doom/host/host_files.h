/* DOOM-1 host build: forced into every doomgeneric file (-include), so Doom's fopen sees the same
   files as on our MIPS: only the WAD, registered in memory, read only (src/c/libc/stdio.c). */
#ifndef HOST_FILES_H
#define HOST_FILES_H
#include <stdio.h>

FILE *host_fopen(const char *path, const char *mode);
#define fopen host_fopen

#endif
