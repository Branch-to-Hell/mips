# Evidence

Board photos and videos (with the date and what they show) and each member's individual sheet (WEB-6).

| File | What it shows |
|---|---|
| `2026-11-23_doom6_title_verilator.png` | DOOM-6: Doom's title screen drawn by our CPU in Verilator (`make -C verif/verilator doom-check`: the same pixels as the PC reference) |
| `2026-11-23_doom6_demo_verilator.png` | DOOM-6: frame 150, the E1M1 demo running on our CPU in Verilator (~4.2 frames per second at 25 MHz) |
| `2026-11-26_doom7_title_board.jpg` | DOOM-7: Doom's title screen on the VGA monitor, from `top_doom` on the DE10-Lite (first try) |
| `2026-11-26_doom8_playing_board.jpg` | DOOM-8: playing E1M1 on the board, firing with KEY0 |
| `2026-11-26_tc15_count_value_in1_board.jpg` | TC-15: `count_value_in1` on `program`, register view SW9 + SW4-0 = 01011: HEX `11` `0004` (count = 4) |
| `2026-11-27_tests_pass_modelsim.png` | TC-16: the whole test suite run again on Nov 27 (ModelSim testbenches + assembler errors), all PASS. Commands in `docs/tc16/README.md` |
| `2026-11-26_life_random_board.jpg` | LIFE-6: Game of Life on `top_life`, random board, generation number on HEX, live-cell bar on LEDR |
