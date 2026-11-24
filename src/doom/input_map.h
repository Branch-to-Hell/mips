/* DOOM-8: the board's switches and KEY0 -> Doom key events (docs/contracts.md "Doom controls").
   Shared by the MIPS platform layer (doomgeneric_mips.c) and the host build (host/), so the
   host input test runs the same code. */
#ifndef INPUT_MAP_H
#define INPUT_MAP_H

#include <stdint.h>

/* Inputs as one mask: bits 9..0 = SW9..SW0, bit 10 = KEY0 (1 = up / pressed) */
#define INPUT_KEY0      (1u << 10)
#define INPUT_BITS      11

/* The key Doom gets for the next-weapon switch (SW9): key_nextweapon is unbound by default, so
   main binds it to this code (']': bound to nothing in Doom, only Heretic's inventory) */
#define INPUT_NEXT_WEAPON_KEY ']'

/* DG_GetKey's job: call it with the current inputs; it returns 1 and one event (*pressed,
   *key) while there are events, then 0. The inputs are sampled once per Doom tic (on the first
   call after a 0), and the events of one sample come out on the following calls.
   Held keys (movement, run, strafe, use, fire): press when the input goes to 1, release when it
   goes back to 0. Momentary keys (Enter, Esc, next weapon): press when the switch goes up and the
   release on the next sample (next tic), nothing when it goes down, so a switch left up doesn't
   repeat in the menus. */
int input_get_key(uint32_t inputs, int *pressed, unsigned char *key);

/* The Doom key of each input bit (0 = no key), for the docs and the host test */
unsigned char input_key_of_bit(int bit);

#endif
