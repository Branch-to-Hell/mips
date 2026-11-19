`timescale 1ns/1ps
module pipeline_register_tb;
reg clk=0, reset=1, enable=0, flush=0, valid_in=0;
reg [114:0] data_in=0;
wire [114:0] id_ex_data;
wire [72:0] ex_mem_data;
wire [37:0] mem_wb_data;
wire id_ex_valid, ex_mem_valid, mem_wb_valid;
reg [31:0] fetch_pc=0;
wire [31:0] id_pc, instruction;
wire if_valid;
always #5 clk=~clk;
pipeline_register #(.WIDTH(115)) id_ex(clk,reset,enable,flush,valid_in,data_in,id_ex_valid,id_ex_data);
pipeline_register #(.WIDTH(73)) ex_mem(clk,reset,enable,flush,valid_in,data_in[72:0],ex_mem_valid,ex_mem_data);
pipeline_register #(.WIDTH(38)) mem_wb(clk,reset,enable,flush,valid_in,data_in[37:0],mem_wb_valid,mem_wb_data);
if_id_register if_id(clk,reset,enable,flush,fetch_pc,id_pc,instruction,if_valid);

task tick;
begin @(posedge clk); #1; end
endtask
task check_data;
input v;
input [114:0] d;
begin
    if ({id_ex_valid,ex_mem_valid,mem_wb_valid} !== {3{v}} ||
        id_ex_data !== d || ex_mem_data !== d[72:0] || mem_wb_data !== d[37:0])
        $fatal(1,"Pipeline register enable/reset/flush/valid mismatch");
end
endtask
task check_fetch;
input v;
input [31:0] pc_value, insn;
begin
    if (if_valid !== v || id_pc !== pc_value || instruction !== insn)
        $fatal(1,"IF/ID mismatch: valid=%b pc=%h instruction=%h",if_valid,id_pc,instruction);
end
endtask

initial begin
    #1;
    if_id.im.mem[0]=32'h12345678;
    if_id.im.mem[1]=32'habcdef01;
    tick; check_data(0,0); check_fetch(0,0,0);
    reset=0; enable=1; valid_in=1; data_in={115{1'b1}};
    tick; check_data(1,{115{1'b1}}); check_fetch(1,0,32'h12345678);    // Hold includes valid and RAM output even when inputs change.
    enable=0; valid_in=0; data_in=0; fetch_pc=4;
    tick; check_data(1,{115{1'b1}}); check_fetch(1,0,32'h12345678);
    enable=1;
    tick; check_data(0,0); check_fetch(1,4,32'habcdef01);
    valid_in=1; data_in={3'b101, {14{8'ha5}}};
    tick; check_data(1,data_in);    // Flush wins over disabled enable; IF/ID invalid output is masked to NOP.

    enable=0; flush=1;
    tick; check_data(0,0); check_fetch(0,0,0);
    flush=0; enable=1; fetch_pc=0;
    tick; check_data(1,data_in); check_fetch(1,0,32'h12345678);
    reset=1; enable=0;
    tick; check_data(0,0); check_fetch(0,0,0);
    $display("Correct");
    $finish;
end
initial begin #1000; $fatal(1,"Pipeline register test timeout"); end
endmodule
