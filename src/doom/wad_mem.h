/* DOOM-3: the WAD in memory. Shared by the MIPS platform layer and the host build (DOOM-1). */
#ifndef WAD_MEM_H
#define WAD_MEM_H

/* Size in bytes of the IWAD that starts at wad, found from its own header and directory (the
   loader writes no size): the end of the directory or of the last lump, whichever is further.
   max = bytes that may be read from wad. -1 if it doesn't start with "IWAD" or anything in it
   points past max (nothing or garbage was loaded there). */
long wad_size(const unsigned char *wad, long max);

#endif
