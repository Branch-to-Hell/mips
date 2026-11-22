/* Boot code for top_doom (docs/contracts.md "Doom memory"), in the on-chip text at 0x0.
   Waits for KEY0, so the Doom image and the WAD can be loaded into the SDRAM over JTAG
   first (src/tools/wad_load.tcl), then jumps to Doom's crt0 at 0x2000_0000. Needs jr:
   j/jal only reach the 256 MB region of the PC. The simulation starts at 0x2000_0000
   directly (RESET_PC) and doesn't use it. */

    .set    noreorder
    .set    noat
    .section .text.start, "ax", @progbits
    .globl  _start
    .ent    _start
_start:
    lui     $t0, 0xFFFF             # MMIO base 0xFFFF_0000
1:  lw      $t1, 0x14($t0)          # KEY (0xFFFF_0014): bit 0 = KEY0, 1 = pressed
    nop
    andi    $t1, $t1, 1
    beq     $t1, $zero, 1b
    nop
    lui     $t9, 0x2000             # Doom's _start
    jr      $t9
    nop
    .end    _start
