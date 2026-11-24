# Doom on the board (DOOM-7) — lab checklist

Only **after** the level 1 items of the day (Game of Life, drill) pass: Doom never uses the demo build
and never touches the Game of Life `.sof`. Memory map and resets: `docs/contracts.md` "Doom memory".

**Date:**  **Who:**  **Commit:**

## Before the lab (at home)
- [ ] `main` up to date; `make -C src/doom` in WSL → `build/doom/doom.bin` (and `doom_sdram.hex`)
- [ ] The WAD: `build/wad/doom1.wad` (shareware v1.9, 4,196,020 bytes, SHA-1 `5b2e249b9c5133ec987b3ea77596381dc0d6bc1d`)
- [ ] Simulation of the same start: `make -C verif/verilator doom-boot` → `build/verilator/doom/boot_000.png` is the title screen
- [ ] Quartus, revision `top_doom` (from `quartus/`): `quartus_sh --flow compile mips -c top_doom` → `quartus/output_files/top_doom.sof`, no timing violations
- [ ] Copy to the USB drive: `top_doom.sof`, `doom.bin`, `doom1.wad`, `src/tools/wad_load.tcl`, this checklist

## On the board
1. [ ] Program `top_doom.sof` (Quartus Programmer, or `quartus_pgm -c USB-Blaster -m JTAG -o "p;quartus/output_files/top_doom.sof"`).
   The CPU runs `boot.S` from the on-chip text and waits for KEY0. The monitor shows mode A (black).
2. [ ] Load Doom's image at SDRAM offset 0 (`0x2000_0000` for the CPU):
   `system-console -cli --script=src/tools/wad_load.tcl build/doom/doom.bin 0` → `PASS: the SDRAM holds the file byte-exact`
3. [ ] Load the WAD at the default offset `0x0300_0000` (`0x2300_0000`):
   `system-console -cli --script=src/tools/wad_load.tcl build/wad/doom1.wad` → `PASS ...` (note the KB/s it prints: ____ s)
4. [ ] Press **KEY0**: `boot.S` jumps to `0x2000_0000`.
5. [ ] The monitor switches to mode B (320×200 doubled) and shows the title screen about **1.7 s** after KEY0
   (simulation: 42.1M cycles at 25 MHz, `make -C verif/verilator doom-boot`). Photo for the report.
6. [ ] Wait: the demo of E1M1 starts by itself (attract mode, ~5 s after the title). Simulation says
   ~4 frames per second: choppy but at the right game speed. Note what you see (and a short video).
7. [ ] Controls (DOOM-8): see `src/doom/README.md` — Enter (menu), new game, walk, turn, fire, open a door.
   **All switches down before KEY0** (a switch already up sends its key at start: on the title screen any
   key opens the menu). SW8/SW9 are also the HEX debug views: while playing that only changes the HEX.

## If something goes wrong
| What you see | What it means | What to do |
|---|---|---|
| All LEDs on, HEX `bAd1Ad` | No valid WAD at `0x2300_0000` | `wad_verify build/wad/doom1.wad` in System Console; load it again (step 3), KEY1, reload `doom.bin`, KEY0 |
| LEDR9 on, HEX `E` + cause + address | CPU-14 halt (bad load/store/fetch) | Write down HEX; SW8 up shows the PC (bits 23..0): `mips-linux-gnu-addr2line -f -e build/doom/doom.elf 0x20xxxxxx` |
| Black screen, no halt, nothing after KEY0 | Stuck in `boot.S` or in Doom | SW9 up + SW4-0 = register number shows registers on HEX (`$ra` = 31, `$sp` = 29); compare with the simulation |
| `wad_load` says no JTAG master | The board isn't running `top_doom` | Program the `.sof` again (step 1) |
| Picture with wrong colors or garbage | Palette or SDRAM timing | Run `sdram_test` (revision `sdram_test`, PLT-9) to check the SDRAM; photo + note |

**KEY1** resets the CPU only (never the SDRAM controller): the CPU goes back to `boot.S`. Doom has already
changed its own `.data`, so **load `doom.bin` again** (step 2) before KEY0. The WAD stays.
A power-off loses both files: steps 1-4 again.

## Result
| Step | OK? | Notes (times, photos, errors) |
|---|---|---|
| Image + WAD loaded | | |
| Title screen | | |
| Demo running | | |
| Controls | | |
