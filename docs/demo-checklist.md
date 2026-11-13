# Demo validation checklist

Run this **twice before Nov 30** (Validation 1: Thu Nov 26, Validation 2: Fri Nov 27) and once more right before presenting on Mon Nov 30.
Always use the **frozen build** (tag `demo`): never a newer `.sof` or `.mif`.

**Date:**  **Who:**  **Tag / commit:** 

## Setup
- [ ] Laptop with Quartus Programmer, USB-Blaster driver working
- [ ] `.sof` and `.mif` files from the `demo` tag (also on a USB drive)
- [ ] DE10-Lite + USB cable, VGA monitor + VGA cable tested
- [ ] Switch/key mapping card printed or on screen

## Level 1 — CPU + Game of Life (must pass)
- [ ] Board programs without errors
- [ ] Test programs pass (results on LEDs/HEX match the expected values)
- [ ] Professor drill: an unseen MARS program assembled, loaded and verified in under 15 minutes
- [ ] HEX debug view shows the right register values
- [ ] Game of Life appears on the monitor right after programming
- [ ] Run mode: KEY1 run/pause, speed switches, pattern switches, KEY0 reset
- [ ] Edit mode: cursor follows the switches, KEY0 toggles a cell
- [ ] HEX shows the generation number; LEDs show the live-cell bar
- [ ] Runs for 5 minutes with no freeze or glitch

## Level 2 — Doom (if we have it)
- [ ] WAD loads into SDRAM
- [ ] Title screen appears; controls respond
- [ ] Switching back to the Game of Life build works (we can always fall back)

## Website
- [ ] Live URL opens on the classroom network / a phone

## Result
| Validation | Date | All passed? | Problems found |
|---|---|---|---|
| 1 | | | |
| 2 | | | |
