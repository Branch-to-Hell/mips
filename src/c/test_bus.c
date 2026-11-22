/* CPU-7 byte lanes on every device of the bus (life_system):
     data and stack (data_memory, 4 byte banks), MMIO registers, framebuffer B (mode B)
   sb/sh must change only their bytes, big-endian: the byte at the lowest address is
   bits 31..24 of the word. Then the pass code (LEDR = 0x3FF, HEX = 0x00600D), and last
   an sb to framebuffer A, which only takes whole words: the CPU must halt with
   cause 3 (store) at that sb, address 0x10040003 (ref_sim.py does the same).
   On a failure: HEX = 0xBAD0nn and main returns nn (the first failed check), no halt. */

#define LEDR  (*(volatile unsigned *)0xFFFF0018)
#define HEX   (*(volatile unsigned *)0xFFFF001C)
#define FB_A  ((volatile unsigned char *)0x10040000)
#define FB_B  ((volatile unsigned *)0x10050000)

static int first_failure;

static void check(int number, int ok)
{
    if (!ok && !first_failure)
        first_failure = number;
}

static volatile unsigned data_word;             /* .bss: the data region */

/* The 4 bytes and 2 halves of one word, through volatile pointers so GCC keeps sb/sh */
static void lanes(volatile unsigned *w, int base)
{
    volatile unsigned char *b = (volatile unsigned char *)w;
    volatile unsigned short *h = (volatile unsigned short *)w;

    *w = 0x11223344;
    b[0] = 0xAA;                                /* bits 31..24 */
    check(base + 0, *w == 0xAA223344);
    b[3] = 0xDD;                                /* bits 7..0 */
    check(base + 1, *w == 0xAA2233DD);
    b[1] = 0xBB;
    b[2] = 0xCC;
    check(base + 2, *w == 0xAABBCCDD);
    h[1] = 0x5566;                              /* bits 15..0 */
    check(base + 3, *w == 0xAABB5566);
    h[0] = 0x7788;                              /* bits 31..16 */
    check(base + 4, *w == 0x77885566);
    check(base + 5, b[0] == 0x77 && b[3] == 0x66 && h[1] == 0x5566);   /* lbu, lhu */
    check(base + 6, ((volatile signed char *)w)[0] == 0x77 &&
                    ((volatile signed char *)w)[2] == 0x55);           /* lb */
    b[1] = 0xF0;
    check(base + 7, ((volatile signed char *)w)[1] == -16 &&
                    ((volatile short *)w)[0] == (short)0x77F0);       /* sign extension */
}

int main(void)
{
    volatile unsigned stack_word;               /* on the stack region */

    lanes(&data_word, 10);
    lanes(&stack_word, 20);

    /* MMIO: a byte or half store changes only its bytes of the register */
    HEX = 0x123456;
    *(volatile unsigned char *)0xFFFF001F = 0x78;           /* HEX bits 7..0 */
    check(30, HEX == 0x123478);
    *(volatile unsigned short *)0xFFFF001E = 0xABCD;        /* HEX bits 15..0 */
    check(31, HEX == 0x12ABCD);
    *(volatile unsigned char *)0xFFFF001E = 0x00;           /* HEX bits 15..8 */
    check(32, HEX == 0x1200CD);
    *(volatile unsigned char *)0xFFFF001D = 0x34;           /* HEX bits 23..16 */
    check(35, HEX == 0x3400CD);
    LEDR = 0x3FF;
    *(volatile unsigned char *)0xFFFF001B = 0x0F;           /* LEDR bits 7..0 */
    check(33, LEDR == 0x30F);
    check(34, *(volatile unsigned char *)0xFFFF001E == 0x00);   /* lbu from MMIO */

    /* Framebuffer B: one byte per pixel, pixel 4n in bits 31..24 */
    FB_B[0] = 0x01020304;
    ((volatile unsigned char *)FB_B)[2] = 0xEE;             /* pixel 2 */
    check(40, FB_B[0] == 0x0102EE04);
    ((volatile unsigned short *)FB_B)[0] = 0x0A0B;          /* pixels 0 and 1 */
    check(41, FB_B[0] == 0x0A0BEE04);

    if (first_failure) {
        HEX = 0xBAD000 | first_failure;
        return first_failure;
    }
    LEDR = 0x3FF;
    HEX = 0x00600D;

    FB_A[3] = 1;                                /* byte store to framebuffer A: halt (cause 3) */
    return 99;                                  /* never reached */
}
