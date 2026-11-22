/* Linker script for C programs on our MIPS (TC-9). Memory map: docs/contracts.md "Memory map".

   The CPU is Harvard: instruction memory is only fetched, never read by lw/lb. So the text
   region holds only code, and every constant (.rodata) goes to the data region with .data.
   Both are loaded at configuration time (instruction banks + <name>_data.hex), so nothing is
   copied at startup: crt0.S only sets $sp and zeroes .bss. A reset does not restore .data. */

OUTPUT_FORMAT("elf32-tradbigmips")
OUTPUT_ARCH(mips)
ENTRY(_start)

MEMORY
{
    TEXT  (rx)  : ORIGIN = 0x00000000, LENGTH = 16K   /* PC reset value = 0 */
    DATA  (rw)  : ORIGIN = 0x10010000, LENGTH = 16K   /* MARS .data base */
    STACK (rw)  : ORIGIN = 0x7FFFE000, LENGTH = 4K
}

SECTIONS
{
    .text : {
        KEEP(*(.text.start))        /* crt0's _start must be at address 0 */
        *(.text .text.*)
    } > TEXT

    .rodata : {
        *(.rodata .rodata.*)
    } > DATA

    .data : {
        *(.data .data.*)
        *(.sdata .sdata.*)          /* empty with -G0, kept in case an object file has it */
    } > DATA

    .bss (NOLOAD) : {
        . = ALIGN(4);
        _bss_start = .;
        *(.sbss .sbss.*)
        *(.bss .bss.*)
        *(COMMON)
        . = ALIGN(4);
        _bss_end = .;               /* crt0 zeroes [_bss_start, _bss_end) one word at a time */
    } > DATA

    _data_end = .;                  /* first free byte of the data region (heap start, TC-10) */
    _stack_top = ORIGIN(STACK) + LENGTH(STACK);

    /* ELF bookkeeping that is not code or data */
    /DISCARD/ : {
        *(.reginfo) *(.MIPS.abiflags) *(.MIPS.options) *(.pdr) *(.mdebug.*)
        *(.gnu.attributes) *(.comment) *(.note.*) *(.eh_frame) *(.eh_frame_hdr)
    }
}
