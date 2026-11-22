/* "Hello pixels" (TC-9): the first C program on our CPU.
   Paints a gradient on the mode A framebuffer (128x96, one word per pixel 0x00RRGGBB)
   in red, green, blue and white stripes from a constant table, then shows the pass code on the board.
   It also checks what crt0.S and link.ld set up:
     - .data comes from the data image (bands[] has its initial values),
     - .bss starts at zero (frames is 0 before the first increment). */

#define FB_A   ((volatile unsigned *)0x10040000)
#define WIDTH  128
#define HEIGHT 96
#define LEDR   (*(volatile unsigned *)0xFFFF0018)
#define HEX    (*(volatile unsigned *)0xFFFF001C)

static const unsigned bands[4] = { 0x00FF0000, 0x0000FF00, 0x000000FF, 0x00FFFFFF };  /* .rodata -> data region */
static unsigned frames;                                                               /* .bss */

int main(void)
{
    volatile unsigned *p = FB_A;

    if (frames != 0) {              /* crt0 did not zero .bss */
        HEX = 0xBAD055;
        return 1;
    }

    for (int y = 0; y < HEIGHT; y++) {
        unsigned band = bands[(y >> 3) & 3];    /* stripes of 8 rows (no y / 24: that is multu, CPU-8) */
        for (int x = 0; x < WIDTH; x++) {
            unsigned shade = (unsigned)x << 1;  /* 0..254 left to right */
            *p++ = band & (shade << 16 | shade << 8 | shade);
        }
    }
    frames++;

    LEDR = 0x3FF;
    HEX = 0x00600D;                 /* same pass protocol as the TC-4/TC-5 programs */
    return 0;
}
