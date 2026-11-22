// TC-7: C++ driver for harness_top.sv. Only the clock and the reset: loading, the trace and
// the end of the run are in harness_top.sv, which sets done when the run ended. The command line goes to the plusargs:
//     build/verilator/mips_sim +program=mem/hello_pixels [+max-cycles=N] [+ppm=file.ppm]
#include <memory>
#include "Vharness_top.h"
#include "verilated.h"

int main(int argc, char** argv) {
    auto ctx = std::make_unique<VerilatedContext>();
    ctx->commandArgs(argc, argv);
    auto top = std::make_unique<Vharness_top>(ctx.get());

    // 4 cycles in reset, released after a falling edge (like the ModelSim testbenches)
    const int reset_half_cycles = 8;
    top->clk = 0;
    top->reset = 1;
    top->eval();
    for (long half = 0; !top->done && !ctx->gotFinish(); ++half) {
        top->clk = !top->clk;
        if (half == reset_half_cycles - 1) top->reset = 0;   // clk just went to 0
        top->eval();
        ctx->timeInc(20);                                    // 25 MHz: 20 ns per half cycle
    }
    top->final();
    return 0;
}
