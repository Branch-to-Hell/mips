/* DOOM-3: size of a WAD in memory, from its header and directory.
   WAD layout: "IWAD", lump count, directory offset (header, 12 bytes), then the directory at
   the end of the file: per lump its offset, size and 8-byte name (16 bytes). Every number is
   little-endian, so it is read byte by byte (our CPU is big-endian, the PC little-endian). */
#include <stdint.h>

#include "wad_mem.h"

static uint32_t le32(const unsigned char *p)
{
    return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
}

long wad_size(const unsigned char *wad, long max)
{
    if (max < 12 || wad[0] != 'I' || wad[1] != 'W' || wad[2] != 'A' || wad[3] != 'D')
        return -1;
    uint32_t lumps = le32(wad + 4);
    uint32_t dir = le32(wad + 8);
    if (dir < 12 || dir > (uint32_t)max || lumps > ((uint32_t)max - dir) / 16)
        return -1;

    uint32_t end = dir + lumps * 16;
    for (uint32_t i = 0; i < lumps; i++) {
        const unsigned char *entry = wad + dir + 16 * i;
        uint32_t pos = le32(entry);
        uint32_t size = le32(entry + 4);
        if (pos > (uint32_t)max || size > (uint32_t)max - pos)
            return -1;
        if (pos + size > end)
            end = pos + size;
    }
    return (long)end;
}
