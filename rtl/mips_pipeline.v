// CPU-4: five-stage pipeline, one instruction per cycle after filling the pipeline.
// Separate from the single-cycle mips_cpu until LIFE-6 checks it on the board
// with Game of Life; then it replaces mips_cpu.
// Phase 1: R-type arithmetic/shifts, I-type arithmetic/lw/sw and beq/bne/j/jal/jr.
// CPU-5: hazard_unit stalls IF/ID while the instruction in ID reads a register
// that EX or MEM will still write (no forwarding: the value reaches ID from WB
// through the bypass). Programs need no NOPs for data or load-use hazards.
// CPU-6: beq/bne/j/jal/jr are resolved in ID with ONE delay slot: the
// instruction after a branch/jump always runs, then fetch continues at the
// target. Nothing is flushed. jal writes PC + 8 (the instruction after the
// delay slot) into $ra. The branch compare and jr read operands in ID, so they
// stall like any other consumer.
// CPU-14: visible halt (contracts.md "Halt on invalid access"). A fetch outside
// the text region or misaligned is caught when the instruction reaches ID; a
// load/store with mem_fault = 1 or a misaligned address is caught in MEM. The
// failing instruction writes nothing, older instructions finish, younger ones
// are dropped, and fetch stops until reset. halted/halt_cause/halt_pc/halt_addr
// tell the top level what to show.
// CPU-7/CPU-8: the rest of the MIPS I integer set (contracts.md "ISA", phase 2):
// sltu sltiu xor xori sra sllv srlv srav, byte/half loads and stores with byte
// enables on the bus (mem_be, big-endian lanes), branches against zero
// (bltz bgez blez bgtz bltzal bgezal) resolved in ID like beq/bne, jalr, and
// HI/LO with mult multu div divu mfhi mflo mthi mtlo (mult_div.v, in EX).
// IMEM_INIT is the prefix of four big-endian byte-bank images (_b0..b3.hex).
// RESET_PC = 0 like mips_cpu (contracts.md: text base 0, CPU-13).
module mips_pipeline #(
    parameter IMEM_INIT = "",
    parameter REGS_INIT = "",
    parameter RESET_PC = 32'h0000_0000   // text base; the text region is 16 KB from here
)(
    input clk, reset,
    output [31:0] mem_addr, mem_wdata,
    output mem_we, mem_re,
    // CPU-7: byte enables, mem_be[3] = bits 31..24 = the byte at the lowest address
    // (big-endian, like framebuffer_b). sw = 1111; sh = 1100/0011; sb = 1000 >> addr[1:0].
    // Stores put the byte/half in every lane it could go to (mem_wdata), so a device
    // only has to look at mem_be. Loads read the whole word and the CPU picks the bytes.
    output [3:0] mem_be,
    input [4:0] dbg_sel,
    output [31:0] dbg_value,
    input [31:0] mem_rdata,
    // CPU-14: the top-level decoder sets mem_fault when mem_addr is in no region.
    // The CPU only looks at it while the instruction in MEM is a load/store.
    input mem_fault,
    output reg halted,             // 1 = stopped by a halt; only reset clears it
    output reg [1:0] halt_cause,   // 1 = fetch, 2 = load, 3 = store (0 = running)
    output reg [31:0] halt_pc,     // PC of the instruction that failed
    output reg [31:0] halt_addr    // the bad address (the PC itself for a fetch)
);
// CPU-5: a stall holds fetch_pc and IF/ID and sends a bubble into ID/EX
// (valid_in = 0 below); EX, MEM and WB keep going. CPU-9 will add the
// whole-pipeline memory wait. No flushes: the delay slot always runs (CPU-6).
localparam [31:0] TEXT_BASE = RESET_PC;

// CPU-14: stop = a halt is starting now or already happened. Fetch freezes
// and ID sends only bubbles; EX, MEM and WB drain what is older.
wire stall;
wire fetch_fault, access_fault;
wire stop = halted || fetch_fault || access_fault;
wire if_id_enable = !stall && !stop, id_ex_enable = 1'b1;
wire ex_mem_enable = 1'b1, mem_wb_enable = 1'b1;
wire if_id_flush = 1'b0, id_ex_flush = 1'b0;
wire ex_mem_flush = 1'b0, mem_wb_flush = 1'b0;

// IF: this PC names the fetch request, not the instruction currently in ID.
// While a branch/jump is in ID, fetch_pc already points at its delay slot
// (id_pc + 4), which is fetched on this edge; next_fetch_pc is the address
// fetched on the edge AFTER it: the target if taken, else sequential.
reg [31:0] fetch_pc;
wire [31:0] id_pc, id_instruction;
wire id_valid;
wire redirect;
wire [31:0] redirect_pc;
wire [31:0] next_fetch_pc = redirect ? redirect_pc : fetch_pc + 32'd4;
always @(posedge clk) begin
    if (reset) fetch_pc <= RESET_PC;
    else if (if_id_enable) fetch_pc <= next_fetch_pc;
end
// IF/ID: 64 payload + 1 valid = 65 bits. Detailed reset/enable/update behavior
// is in if_id_register.v; RAM output and saved PC update on the same edge.
if_id_register #(.IMEM_INIT(IMEM_INIT)) if_id(
    .clk(clk), .reset(reset), .enable(if_id_enable), .flush(if_id_flush),
    .fetch_pc(fetch_pc), .pc(id_pc), .instruction(id_instruction), .valid(id_valid)
);

// ID: decode control alongside operands, so they travel with the instruction.
wire reg_dst, alu_src, mem_to_reg, reg_write, mem_read, mem_write;
wire branch, branch_ne, jump, jump_reg, link;
wire branch_z, mem_unsigned;
wire [1:0] alu_op, mem_size;
wire [3:0] md_op;
wire [3:0] id_alu_ctl;
wire [31:0] id_a, id_b, id_imm;
wire [4:0] id_dest = reg_dst ? id_instruction[15:11] : id_instruction[20:16];
wire zero_extend = (id_instruction[31:26] == 6'h0c) || (id_instruction[31:26] == 6'h0d) ||
                   (id_instruction[31:26] == 6'h0e);   // andi, ori, xori
assign id_imm = zero_extend ? {16'd0, id_instruction[15:0]} :
                             {{16{id_instruction[15]}}, id_instruction[15:0]};
control_unit cu(
    .opcode(id_instruction[31:26]), .funct(id_instruction[5:0]), .rt(id_instruction[20:16]),
    .RegDst(reg_dst), .ALUSrc(alu_src), .MemtoReg(mem_to_reg),
    .RegWrite(reg_write), .MemRead(mem_read), .MemWrite(mem_write),
    .Branch(branch), .BranchNE(branch_ne), .Jump(jump), .JumpReg(jump_reg),
    .Link(link), .ALUOp(alu_op),
    .BranchZ(branch_z), .MemSize(mem_size), .MemUnsigned(mem_unsigned), .MdOp(md_op)
);
alu_control aluc(.ALUOp(alu_op), .funct(id_instruction[5:0]),
    .opcode(id_instruction[31:26]), .ALUctl(id_alu_ctl));
wire [31:0] wb_data;
wire [4:0] wb_dest;
wire wb_valid, wb_reg_write;
wire [31:0] rf_a, rf_b;
wire [4:0] id_rs = id_instruction[25:21], id_rt = id_instruction[20:16];
// The shared register_file writes on posedge (single-cycle timing), i.e. at the
// END of the WB cycle. The write-through bypass below gives ID the value being
// written in the same cycle, like a register file that writes in the first half
// of the cycle and reads in the second. $zero is never bypassed.
wire wb_write = wb_valid && wb_reg_write && (wb_dest != 5'd0);
register_file #(.INIT_FILE(REGS_INIT)) rf(
    .clk(clk), .reset(reset), .AR3(dbg_sel), .DR3(dbg_value), .RegWrite(wb_write && !reset),
    .AR1(id_rs), .AR2(id_rt),
    .AW(wb_dest), .DW(wb_data), .DR1(rf_a), .DR2(rf_b)
);
assign id_a = (wb_write && wb_dest == id_rs) ? wb_data : rf_a;
assign id_b = (wb_write && wb_dest == id_rt) ? wb_data : rf_b;

// CPU-6: branch/jump resolution in ID (contracts.md "Pipeline").
// beq/bne compare the ID operands directly (no ALU), targets use PC + 4 of the
// branch, i.e. the delay slot's address, like MIPS and the single-cycle CPU.
// CPU-7: bltz/bgez/bltzal/bgezal (opcode 1, rt[0] = 1 for >= 0) and blez/bgtz
// (opcodes 6/7) compare rs with zero: only its sign bit and a zero test.
wire [31:0] id_pc_plus4 = id_pc + 32'd4;
wire [31:0] branch_target = id_pc_plus4 + {id_imm[29:0], 2'b00};
wire [31:0] jump_target = {id_pc_plus4[31:28], id_instruction[25:0], 2'b00};
wire operands_equal = (id_a == id_b);
wire a_negative = id_a[31];
wire a_zero = (id_a == 32'd0);
reg zero_cond;
always @(*) begin
    case (id_instruction[27:26])
        2'b01:   zero_cond = id_instruction[16] ? !a_negative : a_negative; // bgez(al) : bltz(al)
        2'b10:   zero_cond = a_negative || a_zero;                          // blez
        2'b11:   zero_cond = !a_negative && !a_zero;                        // bgtz
        default: zero_cond = 1'b0;
    endcase
end
wire branch_taken = (branch && (branch_ne ? !operands_equal : operands_equal)) ||
                    (branch_z && zero_cond);
assign redirect = id_valid && (branch_taken || jump || jump_reg);
assign redirect_pc = jump_reg ? id_a : (jump ? jump_target : branch_target);
// jal/jalr/bltzal/bgezal: the link value PC + 8 travels as operand A with B = 0;
// the ALU adds, so EX produces it like any result and WB writes it. jalr writes
// rd (R-type), the others $ra. bltzal/bgezal link even when not taken (MIPS).
wire [31:0] link_value = id_pc + 32'd8;
wire [31:0] ex_a_in = link ? link_value : id_a;
wire [31:0] ex_b_in = link ? 32'd0 : id_b;
wire [4:0] ex_dest_in = (link && id_instruction[31:26] != 6'h00) ? 5'd31 : id_dest;

// CPU-5 hazard detection (hazard_unit.v). Declared here, driven by later stages.
wire ex_valid, ex_reg_write;
wire [4:0] ex_dest;
wire md_busy;
wire mem_valid, mem_reg_write;
wire [4:0] mem_dest;
hazard_unit hu(
    .opcode(id_instruction[31:26]), .funct(id_instruction[5:0]),
    .rs(id_rs), .rt(id_rt), .id_valid(id_valid),
    .ex_valid(ex_valid), .ex_reg_write(ex_reg_write), .ex_dest(ex_dest),
    .mem_valid(mem_valid), .mem_reg_write(mem_reg_write), .mem_dest(mem_dest),
    .md_busy(md_busy), .stall(stall)
);

// CPU-14: a fetch fault is seen on the instruction in ID: its PC (the address
// it was fetched from) is outside the 16 KB text region or not word aligned.
// Every fetched instruction executes (no flush, CPU-6), so this one is real.
assign fetch_fault = id_valid && ((id_pc[31:14] != TEXT_BASE[31:14]) || (id_pc[1:0] != 2'b00));

// ID/EX: 154 payload + 1 valid = 155 bits.
// Payload: PC(32, for halt_pc), A or link value(32), B/store data(32), immediate(32), destination(5), shamt(5),
// ALU control(4), ALUSrc(1), RegWrite(1), MemRead(1), MemWrite(1), MemtoReg(1),
// memory size(2), MemUnsigned(1), HI/LO op(4).
// posedge; enable=0 holds all fields; synchronous reset/flush clears all fields
// and valid regardless of enable; invalid input inserts a bubble. See primitive.
wire [31:0] ex_pc, ex_a, ex_b, ex_imm;
wire [4:0] ex_shamt;
wire [3:0] ex_alu_ctl;
wire ex_alu_src, ex_mem_read, ex_mem_write, ex_mem_to_reg;
wire [1:0] ex_mem_size;
wire ex_mem_unsigned;
wire [3:0] ex_md_op;
pipeline_register #(.WIDTH(154)) id_ex(
    .clk(clk), .reset(reset), .enable(id_ex_enable), .flush(id_ex_flush),
    .valid_in(id_valid && !stall && !stop),   // stalled or halted: a bubble
    .data_in({id_pc, ex_a_in, ex_b_in, id_imm, ex_dest_in, id_instruction[10:6], id_alu_ctl,
              alu_src, reg_write, mem_read, mem_write, mem_to_reg,
              mem_size, mem_unsigned, md_op}),
    .valid_out(ex_valid),
    .data_out({ex_pc, ex_a, ex_b, ex_imm, ex_dest, ex_shamt, ex_alu_ctl,
               ex_alu_src, ex_reg_write, ex_mem_read, ex_mem_write, ex_mem_to_reg,
               ex_mem_size, ex_mem_unsigned, ex_md_op})
);

// EX: all operands/control are from ID/EX, never the current ID instruction.
wire [31:0] ex_result;
alu alu_unit(.ALUctl(ex_alu_ctl), .A(ex_a), .B(ex_alu_src ? ex_imm : ex_b),
    .shamt(ex_shamt), .ALUOut(ex_result), .Zero());
// Dedicated load/store address adder matches the existing memory-bus contract.
wire [31:0] ex_address = ex_a + ex_imm;
// CPU-8: HI/LO unit. HI/LO change only for an instruction that completes: valid
// and not dropped by an older load/store halting in MEM this cycle.
wire [31:0] hi, lo;
wire md_running;
mult_div md(.clk(clk), .reset(reset), .en(ex_valid && !access_fault), .op(ex_md_op),
    .a(ex_a), .b(ex_b), .hi(hi), .lo(lo), .busy(md_running));
// A div in EX makes the divider busy from the next cycle, so the instruction in ID
// (which would reach EX then) already has to wait.
assign md_busy = md_running || (ex_valid && ex_md_op[3] && ex_md_op[1]);
wire [31:0] ex_alu_or_hilo = (ex_md_op == 4'd1) ? hi : (ex_md_op == 4'd2) ? lo : ex_result;
wire [31:0] ex_value = (ex_mem_read || ex_mem_write) ? ex_address : ex_alu_or_hilo;

// EX/MEM: 108 payload + 1 valid = 109 bits.
// Payload: PC(32, for halt_pc), result/address(32), store data(32), destination(5), RegWrite(1),
// MemRead(1), MemWrite(1), MemtoReg(1), memory size(2), MemUnsigned(1).
// posedge; enable holds all fields; synchronous reset/flush clears payload and
// valid even while disabled; invalid input inserts a bubble. valid gates bus.
wire mem_read_ctl, mem_write_ctl, mem_to_reg_ctl;
wire [31:0] mem_pc, mem_value, mem_store_data;
wire [1:0] mem_size_ctl;
wire mem_unsigned_ctl;
pipeline_register #(.WIDTH(108)) ex_mem(
    .clk(clk), .reset(reset), .enable(ex_mem_enable), .flush(ex_mem_flush),
    .valid_in(ex_valid && !access_fault),   // younger than a failing load/store: dropped
    .data_in({ex_pc, ex_value, ex_b, ex_dest, ex_reg_write, ex_mem_read, ex_mem_write, ex_mem_to_reg,
              ex_mem_size, ex_mem_unsigned}),
    .valid_out(mem_valid),
    .data_out({mem_pc, mem_value, mem_store_data, mem_dest, mem_reg_write, mem_read_ctl, mem_write_ctl, mem_to_reg_ctl,
               mem_size_ctl, mem_unsigned_ctl})
);

// MEM: external memory samples EX/MEM address/data/enables at negedge.
// Read data arrives before MEM/WB captures it at the following posedge.
// CPU-14: a load/store in MEM fails if the decoder says the address is in no
// region (mem_fault) or it is misaligned for its size (word: addr[1:0] = 0,
// half: addr[0] = 0, byte: any). It then reaches no device (mem_re/mem_we
// stay 0) and enters MEM/WB as a bubble, so nothing is written.
// mem_fault must depend only on mem_addr (not on mem_re/mem_we): no loop.
localparam [1:0] SIZE_BYTE = 2'd0, SIZE_HALF = 2'd1;
wire [1:0] byte_off = mem_value[1:0];
wire misaligned = (mem_size_ctl == SIZE_BYTE) ? 1'b0 :
                  (mem_size_ctl == SIZE_HALF) ? byte_off[0] : (byte_off != 2'b00);
wire mem_access = mem_valid && (mem_read_ctl || mem_write_ctl);
assign access_fault = mem_access && (mem_fault || misaligned);
assign mem_addr = mem_value;
// CPU-7 byte lanes (big-endian): offset 0 is bits 31..24. 1111 when MEM has no load/store
// (a bubble's payload is all zeros = byte size), so the top level's decoder, which also
// looks at mem_be (framebuffer A takes whole words only), gives a clean answer.
assign mem_be = !mem_access ? 4'b1111 :
                (mem_size_ctl == SIZE_BYTE) ? (4'b1000 >> byte_off) :
                (mem_size_ctl == SIZE_HALF) ? (byte_off[1] ? 4'b0011 : 4'b1100) : 4'b1111;
assign mem_wdata = (mem_size_ctl == SIZE_BYTE) ? {4{mem_store_data[7:0]}} :
                   (mem_size_ctl == SIZE_HALF) ? {2{mem_store_data[15:0]}} : mem_store_data;
// Loads: pick the byte/half from the word and sign- or zero-extend it.
wire [7:0] load_byte = (byte_off == 2'd0) ? mem_rdata[31:24] : (byte_off == 2'd1) ? mem_rdata[23:16] :
                       (byte_off == 2'd2) ? mem_rdata[15:8] : mem_rdata[7:0];
wire [15:0] load_half = byte_off[1] ? mem_rdata[15:0] : mem_rdata[31:16];
wire [31:0] load_value = (mem_size_ctl == SIZE_BYTE) ? {{24{!mem_unsigned_ctl & load_byte[7]}}, load_byte} :
                         (mem_size_ctl == SIZE_HALF) ? {{16{!mem_unsigned_ctl & load_half[15]}}, load_half} :
                         mem_rdata;
assign mem_re = mem_valid && mem_read_ctl && !access_fault && !reset;
assign mem_we = mem_valid && mem_write_ctl && !access_fault && !reset;

// MEM/WB: 38 payload + 1 valid = 39 bits.
// Payload: selected register value(32), destination(5), RegWrite(1).
// posedge; enable holds; synchronous reset/flush clears payload and valid even
// if disabled. valid gates the register write at the end of the WB cycle
// (next posedge), bypassed to ID during that cycle.
// Selecting memory/ALU data before this register avoids retaining unused data.
pipeline_register #(.WIDTH(38)) mem_wb(
    .clk(clk), .reset(reset), .enable(mem_wb_enable), .flush(mem_wb_flush),
    .valid_in(mem_valid && !access_fault),
    .data_in({mem_to_reg_ctl ? load_value : mem_value, mem_dest, mem_reg_write}),
    .valid_out(wb_valid), .data_out({wb_data, wb_dest, wb_reg_write})
);

/* CPU-14 halt state. Only reset leaves it.
An access fault in MEM is always older than a fetch fault in ID, so when both
happen (in the same cycle, or the load/store reaches MEM after a fetch fault while the
pipeline drains) the access fault is the one reported. After an access fault,
nothing else can reach MEM, so the report never changes again.
*/
always @(posedge clk) begin
    if (reset) begin
        halted <= 1'b0;
        halt_cause <= 2'd0;
        halt_pc <= 32'd0;
        halt_addr <= 32'd0;
    end else if (access_fault) begin
        halted <= 1'b1;
        halt_cause <= mem_write_ctl ? 2'd3 : 2'd2;
        halt_pc <= mem_pc;
        halt_addr <= mem_value;
    end else if (fetch_fault && !halted) begin
        halted <= 1'b1;
        halt_cause <= 2'd1;
        halt_pc <= id_pc;
        halt_addr <= id_pc;
    end
end
endmodule
