/* Linker script for Doom (DOOM-5): docs/contracts.md "Doom memory".
   Everything Doom has (code, constants, data, .bss, heap) lives in the SDRAM from 0x2000_0000;
   its stack is the on-chip data region. The image (.text .rodata .data) is loaded over JTAG at
   SDRAM offset 0 (src/tools/wad_load.tcl), so crt0 copies nothing; it zeroes .bss.
   Same crt0 as the other C programs (src/c/crt0.S): it takes _stack_top, _bss_start and
   _bss_end from here, and libc's sbrk takes _data_end and _heap_end. */

OUTPUT_FORMAT("elf32-tradbigmips")
OUTPUT_ARCH(mips)
ENTRY(_start)

MEMORY
{
    SDRAM (rwx) : ORIGIN = 0x20000000, LENGTH = 0x03000000   /* 48 MB: the WAD starts at 0x2300_0000 */
}

SECTIONS
{
    .text : {
        KEEP(*(.text.start))        /* crt0's _start at 0x2000_0000, where boot.S jumps */
        *(.text .text.*)
    } > SDRAM

    .rodata : {
        *(.rodata .rodata.*)
    } > SDRAM

    .data : {
        *(.data .data.*)
        *(.sdata .sdata.*)
    } > SDRAM

    .bss (NOLOAD) : {
        . = ALIGN(4);
        _bss_start = .;
        *(.sbss .sbss.*)
        *(.bss .bss.*)
        *(COMMON)
        . = ALIGN(4);
        _bss_end = .;
    } > SDRAM

    _data_end = .;                              /* the heap starts here */
    _heap_end = ORIGIN(SDRAM) + LENGTH(SDRAM);  /* 0x2300_0000 */
    _stack_top = 0x10014000;                    /* on-chip data region (crt0: $sp = _stack_top - 16) */

    /DISCARD/ : {
        *(.reginfo) *(.MIPS.abiflags) *(.MIPS.options) *(.pdr) *(.mdebug.*)
        *(.gnu.attributes) *(.comment) *(.note.*) *(.eh_frame) *(.eh_frame_hdr)
    }
}
