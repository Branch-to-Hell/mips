# tc16_trace.asm - TC-16: one traced instruction per format on mips_pipeline
# Traced in verif/trace_tb.v (do trace.do), which writes verif/traces/trace_R.txt, trace_I.txt, trace_J.txt.
#   R: add $t2, $t0, $t1    5 + 7 = 12 (professor's funct 0x21)
#   I: lw  $t3, 4($s1)      reads 0xCAFE1234 from 0x10010004 (sign-extended offset, MemtoReg)
#   J: j   j_target         skips addi $t4, $zero, 1, so $t4 stays 0 (visible effect)
# The nops keep every operand 3 instructions away from its producer, so the traced
# instructions never stall and each one shows the 5 stages in 5 consecutive cycles
# (stalls and the delay slot are covered by TC-5: tc5_*.asm, cpu5_tb, cpu6_tb).
.data
vals:   .word 0x11111111, 0xCAFE1234

.text
main:
    lui  $s1, 0x1001            # s1 = 0x10010000 (data base)
    addi $t0, $zero, 5
    addi $t1, $zero, 7
    addi $t3, $zero, -1         # t3 = 0xFFFFFFFF before the lw
    addi $t4, $zero, 0
    nop
    nop
r_add:
    add  $t2, $t0, $t1          # R-type traced
i_lw:
    lw   $t3, 4($s1)            # I-type traced
j_j:
    j    j_target               # J-type traced (the assembler adds the delay-slot nop)
    addi $t4, $zero, 1          # skipped
j_target:
    nop
end:
    j    end
