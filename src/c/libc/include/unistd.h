/* Minimal C library for our MIPS (TC-10): unistd.h */
#ifndef _UNISTD_H
#define _UNISTD_H

#include <stdint.h>

/* Grows the heap by incr bytes and returns its old end, or (void *)-1 with errno = ENOMEM
   when the heap region is full. The heap goes from _data_end to _heap_end (src/c/link.ld). */
void *sbrk(intptr_t incr);

#endif
