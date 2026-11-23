/* DOOM-1: the same doomgeneric build on the PC, without a window, as the reference for the
   Verilator run (DOOM-6) and the board (DOOM-7).
   - Same defines as the MIPS build (CMAP256, 320x200): the frame is 8-bit palette indices.
   - The WAD is read into RAM, its size checked with wad_size() (DOOM-3) and served to Doom's
     fopen("doom1.wad") from memory; every other file fails, like our C library.
   - Time is a counter that only DG_SleepMs advances, so every run is the same.
   - DG_DrawFrame saves each frame as a PPM (palette applied) and stops after the last one.
   Usage: doom_host <doom1.wad> <output dir> [frames]   (make -C src/doom host-run) */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "doomgeneric.h"
#include "doomtype.h"
#include "i_video.h"
#include "wad_mem.h"

extern boolean palette_changed;
extern struct color colors[256];
extern char *pagename;                  /* d_main.c: the full-screen page (TITLEPIC...) */

static unsigned char *wad;
static long wad_len;
static const char *out_dir;
static int frames_max = 40;
static int frame;
static uint32_t now_ms;

/* host_files.h sends Doom's fopen here; this file uses the real one */
FILE *host_fopen(const char *path, const char *mode)
{
    if (mode[0] != 'r' || strchr(mode, '+') || strcmp(path, "doom1.wad"))
        return NULL;
    return fmemopen(wad, (size_t)wad_len, "rb");
}

void DG_Init(void) {}

void DG_DrawFrame(void)
{
    char path[512];
    snprintf(path, sizeof path, "%s/frame_%03d.ppm", out_dir, frame);
    FILE *f = fopen(path, "wb");
    if (!f) {
        perror(path);
        exit(1);
    }
    fprintf(f, "P6\n%d %d\n255\n", DOOMGENERIC_RESX, DOOMGENERIC_RESY);
    for (int i = 0; i < DOOMGENERIC_RESX * DOOMGENERIC_RESY; i++) {
        struct color c = colors[DG_ScreenBuffer[i]];
        fputc(c.r, f);
        fputc(c.g, f);
        fputc(c.b, f);
    }
    fclose(f);
    printf("frame %3d  t=%6u ms  page=%s\n", frame, now_ms, pagename ? pagename : "-");
    palette_changed = false;
    if (++frame >= frames_max) {
        printf("%d frames saved in %s\n", frame, out_dir);
        exit(0);
    }
}

void DG_SleepMs(uint32_t ms) { now_ms += ms; }
uint32_t DG_GetTicksMs(void) { return now_ms; }
int DG_GetKey(int *pressed, unsigned char *key) { (void)pressed; (void)key; return 0; }
void DG_SetWindowTitle(const char *title) { (void)title; }

int main(int argc, char **argv)
{
    if (argc < 3) {
        fprintf(stderr, "usage: %s <doom1.wad> <output dir> [frames]\n", argv[0]);
        return 2;
    }
    out_dir = argv[2];
    if (argc > 3)
        frames_max = atoi(argv[3]);

    FILE *f = fopen(argv[1], "rb");
    if (!f || fseek(f, 0, SEEK_END) || (wad_len = ftell(f)) <= 0) {
        perror(argv[1]);
        return 1;
    }
    wad = malloc((size_t)wad_len);
    rewind(f);
    if (fread(wad, 1, (size_t)wad_len, f) != (size_t)wad_len) {
        perror(argv[1]);
        return 1;
    }
    fclose(f);

    /* DOOM-3's size check, on the real file: the directory must give the file's exact size */
    long size = wad_size(wad, wad_len);
    printf("WAD %s: %ld bytes, wad_size() = %ld\n", argv[1], wad_len, size);
    if (size != wad_len) {
        fprintf(stderr, "wad_size() doesn't match the file size\n");
        return 1;
    }

    static char *dargv[] = { "doom", "-iwad", "doom1.wad", NULL };
    doomgeneric_Create(3, dargv);
    for (;;)
        doomgeneric_Tick();
}
