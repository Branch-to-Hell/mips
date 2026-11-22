/* Minimal C library for our MIPS (TC-10): sys/stat.h. No file system: they always fail. */
#ifndef _SYS_STAT_H
#define _SYS_STAT_H

#include <sys/types.h>

struct stat {
    off_t st_size;
    mode_t st_mode;
};

#define S_IFMT  0170000
#define S_IFDIR 0040000
#define S_IFREG 0100000
#define S_ISDIR(m) (((m) & S_IFMT) == S_IFDIR)
#define S_ISREG(m) (((m) & S_IFMT) == S_IFREG)

int stat(const char *path, struct stat *buf);
int mkdir(const char *path, mode_t mode);

#endif
