`timescale 1ns/1ps
// Full CPU-4 program: independent instructions, memory traffic, and a consumer
// scheduled with two intervening instructions (WB -> ID write-through bypass).
// Runs the pipeline with RESET_PC = 0 (the contract's text base, CPU-13).
// Also checks cycle-by-cycle PC/instruction pairing, fill, and reset effects.
module cpu4_tb;
reg clk=0, reset=1;
wire [31:0] mem_addr, mem_wdata, mem_rdata;
wire mem_we, mem_re;
integer i,n=0,cycle,index;
reg [31:0] words[0:127], values[0:127];
reg [4:0] targets[0:127];
reg stores[0:127], loads[0:127];
reg [31:0] addresses[0:127], store_values[0:127];
mips_pipeline #(.RESET_PC(32'h0)) dut(.clk(clk),.reset(reset),.mem_addr(mem_addr),.mem_wdata(mem_wdata),
    .mem_we(mem_we),.mem_re(mem_re),.mem_rdata(mem_rdata));
data_memory dm(.clk(clk),.MemRead(mem_re),.MemWrite(mem_we),.Address(mem_addr),
    .WriteData(mem_wdata),.ReadData(mem_rdata));
always #5 clk=~clk;

task emit;
input [31:0] insn;
input [4:0] target;
input [31:0] result;
begin
    words[n]=insn; dut.if_id.im.write_word(n, insn);
    targets[n]=target; values[n]=result;
    stores[n]=0; loads[n]=0; addresses[n]=0; store_values[n]=0;
    n=n+1;
end
endtask

task memory_op;
input [31:0] insn;
input [4:0] target;
input [31:0] result, addr;
input store;
begin
    emit(insn,target,result);
    stores[n-1]=store; loads[n-1]=!store;
    addresses[n-1]=addr; store_values[n-1]=result;
end
endtask

initial begin
    #1;
    for(i=0;i<4096;i=i+1) begin dut.if_id.im.write_word(i, 0); dm.mem[i]=0; end
    for(i=0;i<32;i=i+1) dut.rf.registers[i]=0;
    dut.rf.registers[16]=32'h10010000;
    dut.rf.registers[17]=10;
    dut.rf.registers[18]=3;
    dut.rf.registers[19]=32'hffffffff;
    dm.mem[0]=32'h12345678;
    dm.mem[1]=32'h89abcdef;
    // Read only preinitialized source registers; different live controls overlap.
    emit({6'h00,5'd17,5'd18,5'd8,5'd0,6'h20},8,13); // add
    emit({6'h08,5'd18,5'd9,16'hfffe},9,1); // addi negative
    emit({6'h00,5'd17,5'd18,5'd10,5'd0,6'h22},10,7); // sub
    emit({6'h0c,5'd19,5'd11,16'hffff},11,32'hffff); // andi
    emit({6'h0d,5'd0,5'd12,16'h8000},12,32'h8000); // ori
    emit({6'h0a,5'd19,5'd13,16'h0000},13,1); // signed slti
    emit({6'h0f,5'd0,5'd14,16'h8000},14,32'h80000000); // lui
    emit({6'h00,5'd0,5'd18,5'd15,5'd4,6'h00},15,48); // sll
    emit({6'h00,5'd0,5'd17,5'd20,5'd1,6'h02},20,5); // srl
    emit({6'h00,5'd17,5'd18,5'd21,5'd0,6'h24},21,2); // and
    emit({6'h00,5'd17,5'd18,5'd22,5'd0,6'h25},22,11); // or
    emit({6'h00,5'd17,5'd18,5'd23,5'd0,6'h27},23,32'hfffffff4); // nor
    emit({6'h00,5'd19,5'd18,5'd24,5'd0,6'h2a},24,1); // slt
    memory_op({6'h23,5'd16,5'd25,16'd0},25,32'h12345678,32'h10010000,0);
    memory_op({6'h2b,5'd16,5'd17,16'd8},0,10,32'h10010008,1);
    memory_op({6'h23,5'd16,5'd26,16'd4},26,32'h89abcdef,32'h10010004,0);
    memory_op({6'h2b,5'd16,5'd18,16'd12},0,3,32'h1001000c,1);
    memory_op({6'h23,5'd16,5'd27,16'd8},27,10,32'h10010008,0);
    emit({6'h08,5'd0,5'd0,16'd123},0,0); // $zero protected
    // Minimum safe spacing without hazard unit: two intervening instructions.
    emit({6'h08,5'd0,5'd8,16'd40},8,40);
    emit(0,0,0);
    emit(0,0,0);
    emit({6'h08,5'd8,5'd9,16'd2},9,42);
    emit(0,0,0);
    emit(0,0,0);
    memory_op({6'h2b,5'd16,5'd9,16'd16},0,42,32'h10010010,1);

    @(posedge clk); #1;
    if ({dut.id_valid,dut.ex_valid,dut.mem_valid,dut.wb_valid} !== 4'b0000)
        $fatal(1,"Reset must empty every stage");
    reset=0;
    for(cycle=0;cycle<n+4;cycle=cycle+1) begin
        @(posedge clk); #1;
        if (dut.id_pc !== cycle*4 || dut.id_instruction !== dut.if_id.im.read_word(cycle))
            $fatal(1,"IF/ID PC/instruction misaligned at cycle %0d",cycle);
        if (dut.id_valid !== 1'b1 || dut.ex_valid !== (cycle>=1) ||
            dut.mem_valid !== (cycle>=2) || dut.wb_valid !== (cycle>=3))
            $fatal(1,"Pipeline fill mismatch at cycle %0d",cycle);
        index=cycle-2;
        if(index>=0 && index<n) begin
            if(mem_we !== stores[index] || mem_re !== loads[index])
                $fatal(1,"Memory enables not associated with instruction %0d",index);
            if(stores[index] || loads[index]) begin
                if(mem_addr !== addresses[index]) $fatal(1,"Bad memory address at %0d",index);
                if(stores[index] && mem_wdata !== store_values[index]) $fatal(1,"Bad store data");
            end
        end else if(mem_we !== 0 || mem_re !== 0) $fatal(1,"Unexpected memory access");
        index=cycle-3;
        if(index>=0 && index<n && targets[index]!=0) begin
            if(!dut.wb_valid || !dut.wb_reg_write || dut.wb_dest !== targets[index] || dut.wb_data !== values[index])
                $fatal(1,"WB mismatch instruction %0d: dest=%d value=%h expected=%h",index,dut.wb_dest,dut.wb_data,values[index]);
        end else if(dut.wb_valid && dut.wb_reg_write && dut.wb_dest!=0)
            $fatal(1,"Unexpected architectural register write");
        // The register file commits at the end of the WB cycle (this posedge).
        index=cycle-4;
        if(index>=0 && index<n && targets[index]!=0 && dut.rf.registers[targets[index]] !== values[index])
            $fatal(1,"Register write did not commit at the end of WB (instruction %0d)",index);
    end
    if(dm.mem[2] !== 10 || dm.mem[3] !== 3 || dm.mem[4] !== 42 || dut.rf.registers[0] !== 0)
        $fatal(1,"Final memory/zero-register mismatch");
    // Reset during overlap of an uncommitted WB write and a pending MEM store.
    reset=1;
    @(posedge clk); #1;
    dut.rf.registers[8]=123;
    dm.mem[0]=32'hfeedface;
    dut.if_id.im.write_word(0, {6'h08,5'd0,5'd8,16'd55});
    dut.if_id.im.write_word(1, {6'h2b,5'd16,5'd17,16'd0});
    for(i=2;i<4096;i=i+1) dut.if_id.im.write_word(i, 0);
    reset=0;
    repeat(4) begin @(posedge clk); #1; end
    if(!mem_we || !dut.wb_reg_write || !dut.wb_valid) $fatal(1,"Reset test not exercising active writes");
    reset=1; #1;
    if(mem_we !== 0 || mem_re !== 0) $fatal(1,"Reset must block memory immediately");
    @(negedge clk); #1;
    if(dut.rf.registers[8] !== 123 || dm.mem[0] !== 32'hfeedface)
        $fatal(1,"Reset allowed a register/memory side effect");
    @(posedge clk); #1;
    if(dut.rf.registers[8] !== 123)
        $fatal(1,"Reset allowed the pending WB register write");
    if({dut.id_valid,dut.ex_valid,dut.mem_valid,dut.wb_valid} !== 0 || dut.fetch_pc !== 0)
        $fatal(1,"Reset did not clear pipeline and restart fetch");
    reset=0;
    repeat(6) begin @(negedge clk); #1; end
    if(dut.rf.registers[8] !== 55 || dm.mem[0] !== 10)
        $fatal(1,"Restart after reset failed");
    $display("PASS",n);
    $finish;
end
initial begin #10000; $fatal(1,"CPU-4 timeout"); end
endmodule
