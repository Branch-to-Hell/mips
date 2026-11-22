/* Minimal C library for our MIPS (TC-10): sbrk and malloc/free/calloc/realloc.

   Heap: from _data_end (the end of .bss) to _heap_end (the end of the data region), both
   from src/c/link.ld. sbrk moves the heap's end up; it never gives memory back.

   malloc is a first-fit allocator over the blocks in address order. Each block has an
   8-byte header (its size, header included, and whether it is used) followed by the
   payload, so payloads are 8-byte aligned (good for doubles and long long). free marks
   the block free and joins it with the free blocks after it; malloc also joins free
   neighbors while it searches, and splits a block when the rest is big enough.
   Programs use malloc or sbrk, not both: the blocks must stay contiguous.
   Doom allocates one big zone at start and manages it itself (z_zone.c), so this
   simple allocator is enough. */
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <errno.h>
#include <unistd.h>

extern char _data_end[], _heap_end[];      /* link.ld */

static char *heap_top;                      /* current end of the heap (0 = not started) */

void *sbrk(intptr_t incr)
{
    if (!heap_top)
        heap_top = (char *)(((uintptr_t)_data_end + 7) & ~(uintptr_t)7);
    char *old = heap_top;
    if (incr > _heap_end - heap_top || incr < _data_end - heap_top) {
        errno = ENOMEM;
        return (void *)-1;
    }
    heap_top += incr;
    return old;
}

typedef struct block {
    size_t size;        /* bytes, header included, multiple of 8 */
    size_t used;        /* 1 = allocated */
} block;

#define HEADER    sizeof(block)             /* 8 */
#define MIN_BLOCK (HEADER + 8)              /* smallest block worth splitting off */

/* Blocks are in [heap_start, heap_end). Two hints keep malloc from walking every block:
   every block before first_free is used, and last is the block that ends at heap_end. */
static block *heap_start, *heap_end, *first_free, *last;

static block *next_block(block *b)
{
    return (block *)((char *)b + b->size);
}

/* Join b with the free blocks that follow it */
static void join_free(block *b)
{
    block *n;
    while ((n = next_block(b)) < heap_end && !n->used)
        b->size += n->size;
    if (next_block(b) == heap_end)
        last = b;
}

static void split(block *b, size_t size)
{
    if (b->size - size >= MIN_BLOCK) {
        block *rest = (block *)((char *)b + size);
        rest->size = b->size - size;
        rest->used = 0;
        b->size = size;
        if (last == b)
            last = rest;
        if (rest < first_free)
            first_free = rest;
    }
}

void *malloc(size_t size)
{
    if (size == 0 || size > (size_t)(_heap_end - _data_end))
        return NULL;
    size_t need = (size + HEADER + 7) & ~(size_t)7;

    int all_used = 1;                       /* every block so far is used: move first_free */
    for (block *b = first_free; b && b < heap_end; b = next_block(b)) {
        if (b->used) {
            if (all_used)
                first_free = next_block(b);
            continue;
        }
        all_used = 0;
        join_free(b);
        if (b->size >= need) {
            split(b, need);
            b->used = 1;
            if (first_free == b)
                first_free = next_block(b);
            return b + 1;
        }
    }

    /* No free block is big enough: grow the heap. If the last block is free, grow it. */
    block *b = (last && !last->used) ? last : heap_end;
    size_t have = (b == heap_end) ? 0 : b->size;
    char *p = sbrk(need - have);
    if (p == (char *)-1)
        return NULL;
    if (!heap_start)
        heap_start = first_free = b = (block *)p;
    heap_end = (block *)(p + need - have);
    b->size = need;
    b->used = 1;
    last = b;
    if (first_free == b)
        first_free = heap_end;
    return b + 1;
}

void free(void *ptr)
{
    if (!ptr)
        return;
    block *b = (block *)ptr - 1;
    b->used = 0;
    join_free(b);
    if (b < first_free)
        first_free = b;
}

void *calloc(size_t count, size_t size)
{
    size_t total = count * size;
    if (size && total / size != count)      /* overflow */
        return NULL;
    void *p = malloc(total);
    return p ? memset(p, 0, total) : NULL;
}

void *realloc(void *ptr, size_t size)
{
    if (!ptr)
        return malloc(size);
    if (size == 0) {
        free(ptr);
        return NULL;
    }
    block *b = (block *)ptr - 1;
    size_t need = (size + HEADER + 7) & ~(size_t)7;
    join_free(b);                           /* use the free space right after it */
    if (first_free > b && first_free < next_block(b))
        first_free = next_block(b);         /* it was one of the blocks b just took */
    if (b->size >= need) {
        split(b, need);
        return ptr;
    }
    void *bigger = malloc(size);
    if (!bigger)
        return NULL;
    memcpy(bigger, ptr, b->size - HEADER);
    free(ptr);
    return bigger;
}
