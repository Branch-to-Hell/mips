/* doomgeneric's platform layer for our MIPS (DOOM-2), and main.
   Built with CMAP256 and 320x200, so Doom's frame is 8-bit palette indices, the format of
   video mode B: DG_ScreenBuffer points at framebuffer B and I_FinishUpdate copies each line
   straight into it. The palette goes to the mode B palette when Doom changes it.
   The WAD is read from the SDRAM as a file in memory (DOOM-3, wad_mem.c).
   Memory map and MMIO: docs/contracts.md. */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include "doomgeneric.h"
#include "doomtype.h"
#include "i_video.h"
#include "wad_mem.h"

#define LEDR       (*(volatile uint32_t *)0xFFFF0018)
#define HEX        (*(volatile uint32_t *)0xFFFF001C)
#define TIMER      (*(volatile uint32_t *)0xFFFF0020)   /* milliseconds since reset */
#define VIDEO_MODE (*(volatile uint32_t *)0xFFFF0024)   /* 1 = mode B */
#define FB_B       ((pixel_t *)0x10050000)              /* 320x200 bytes */
#define PALETTE    ((volatile uint32_t *)0x1005FC00)    /* 256 x 0x00RRGGBB */
#define WAD        ((const unsigned char *)0x23000000)  /* SDRAM + 0x0300_0000, up to its end */
#define WAD_MAX    0x01000000L

/* i_video.c with CMAP256: Doom's palette and "it changed" */
extern boolean palette_changed;
extern struct color colors[256];

void DG_Init(void)
{
    free(DG_ScreenBuffer);              /* doomgeneric_Create allocated one; we draw on framebuffer B */
    DG_ScreenBuffer = FB_B;
    VIDEO_MODE = 1;
}

void DG_DrawFrame(void)
{
    /* The frame is already in framebuffer B (I_FinishUpdate); only the palette is left */
    if (palette_changed) {
        for (int i = 0; i < 256; i++)
            PALETTE[i] = (uint32_t)colors[i].r << 16 | (uint32_t)colors[i].g << 8 | colors[i].b;
        palette_changed = false;
    }
}

void DG_SleepMs(uint32_t ms)
{
    uint32_t start = TIMER;
    while (TIMER - start < ms)
        ;
}

uint32_t DG_GetTicksMs(void)
{
    return TIMER;
}

int DG_GetKey(int *pressed, unsigned char *key)
{
    (void)pressed;
    (void)key;
    return 0;                           /* no keys yet: controls are DOOM-8 */
}

void DG_SetWindowTitle(const char *title)
{
    (void)title;
}

int main(void)
{
    /* DOOM-3: the WAD is in the SDRAM (loaded over JTAG at offset 0x0300_0000). Doom opens it
       with fopen("doom1.wad"), so it is registered as a file in memory; its size comes from its
       own directory. Nothing or a bad file there: LEDs all on, HEX "bAd1Ad", stop here. */
    long size = wad_size(WAD, WAD_MAX);
    if (size < 0 || __mem_file_add("doom1.wad", WAD, size) != 0) {
        LEDR = 0x3FF;
        HEX = 0xBAD1AD;
        for (;;)
            ;
    }

    static char *argv[] = { "doom", "-iwad", "doom1.wad", NULL };
    doomgeneric_Create(3, argv);
    for (;;)
        doomgeneric_Tick();
}
