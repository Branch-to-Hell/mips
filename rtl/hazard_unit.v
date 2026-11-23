/* CPU-5: hazard detection unit for mips_pipeline (no forwarding, contracts.md "Pipeline").
Every operand is read in ID: ALU/memory operands, the branch compare and the jr/jalr address.
The only path from a producer to ID is the WB -> ID bypass, so an instruction in ID must
wait while the instruction in EX or MEM is going to write a register it reads:
    stall = ID uses rs and (EX or MEM writes rs)  or  ID uses rt and (EX or MEM writes rt)
A load in EX is just one case of this (load-use): it stalls 2 cycles, like an ALU producer
right before. $zero never stalls (it is never written).
CPU-8: an instruction that uses HI/LO (mfhi mflo mthi mtlo mult multu div divu) also waits
in ID while a divide is running (md_busy), so it reaches EX only when HI/LO are ready.

While stall = 1, mips_pipeline:
    - keeps fetch_pc and IF/ID (enable = 0): the instruction in ID waits and is read again,
      and a branch/jump in ID does not redirect until its operands are ready;
    - loads a bubble into ID/EX (valid = 0), so nothing is written for the waiting instruction;
    - lets EX, MEM and WB advance, so the producer reaches WB and the stall ends by itself.
*/
module hazard_unit(
    input [5:0] opcode,            // ID instruction [31:26]
    input [5:0] funct,             // ID instruction [5:0]
    input [4:0] rs, rt,            // ID source fields
    input id_valid,
    input ex_valid, ex_reg_write,
    input [4:0] ex_dest,
    input mem_valid, mem_reg_write,
    input [4:0] mem_dest,
    input md_busy,                 // CPU-8: a divide is running or starts in EX now
    output stall
);

// Which fields are sources. Precise decoding avoids false stalls: in I-type ALU
// instructions and loads, rt is the destination; in REGIMM branches it selects the
// branch; j/jal have a target in bits [25:0].
wire r_type   = (opcode == 6'h00);
wire shift    = r_type && (funct == 6'h00 || funct == 6'h02 || funct == 6'h03); // sll srl sra: only rt
wire jump     = (opcode == 6'h02) || (opcode == 6'h03);          // j, jal: no sources
wire branch   = (opcode == 6'h04) || (opcode == 6'h05);          // beq, bne: rs and rt
wire store    = (opcode == 6'h28) || (opcode == 6'h29) || (opcode == 6'h2b); // sb sh sw: base and data
wire uses_rs  = !jump && !shift;   // lui and mfhi/mflo have rs = 0, which never matches
wire uses_rt  = r_type || branch || store;
wire uses_hilo = r_type && ((funct[5:2] == 4'b0100) || (funct[5:2] == 4'b0110)); // 0x10-0x13, 0x18-0x1B

// A pending write: valid instruction, RegWrite, and not $zero.
wire ex_writes  = ex_valid  && ex_reg_write  && (ex_dest  != 5'd0);
wire mem_writes = mem_valid && mem_reg_write && (mem_dest != 5'd0);

wire rs_hazard = uses_rs && ((ex_writes && ex_dest == rs) || (mem_writes && mem_dest == rs));
wire rt_hazard = uses_rt && ((ex_writes && ex_dest == rt) || (mem_writes && mem_dest == rt));
wire hilo_hazard = uses_hilo && md_busy;

assign stall = id_valid && (rs_hazard || rt_hazard || hilo_hazard);

endmodule
