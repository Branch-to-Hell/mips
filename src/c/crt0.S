/* Startup code for C programs (TC-9). Linked first, so _start is at address 0 (PC reset value).
   1. $sp at the top of the stack region, minus the 16-byte argument area the O32 ABI
      lets main write into its caller's frame.
   2. Zero .bss (_bss_start and _bss_end come from link.ld and are word aligned).
   3. Call main(). When it returns, $v0 keeps its return value and the CPU spins on a
      self-jump: the end that ref_sim.py and the testbenches detect ("jumps to itself").
   No .data copy: the data image is loaded at configuration time (see link.ld). */

    .set    noreorder           # we fill the delay slots ourselves
    .set    noat
    .section .text.start, "ax", @progbits
    .globl  _start
    .ent    _start
_start:
    lui     $sp, %hi(_stack_top - 16)
    addiu   $sp, $sp, %lo(_stack_top - 16)
    move    $fp, $zero
    move    $gp, $zero          # -G0: nothing is $gp-relative

    lui     $t0, %hi(_bss_start)
    addiu   $t0, $t0, %lo(_bss_start)
    lui     $t1, %hi(_bss_end)
    addiu   $t1, $t1, %lo(_bss_end)
    beq     $t0, $t1, 2f        # empty .bss
    nop
1:  sw      $zero, 0($t0)
    addiu   $t0, $t0, 4
    bne     $t0, $t1, 1b
    nop

2:  jal     main
    nop
3:  j       3b                  # main returned: stop here
    nop
    .end    _start
