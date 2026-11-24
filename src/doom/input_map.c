/* DOOM-8: the board's switches and KEY0 -> Doom key events. See input_map.h.
   The key codes are the ones doomgeneric binds by default (m_controls.c): KEY_FIRE, KEY_USE,
   KEY_RSHIFT (run), KEY_RALT (strafe), the arrows; Enter and Escape drive the menus
   (key_menu_forward, key_menu_activate). */
#include "input_map.h"

#include "doomkeys.h"

/* bit -> Doom key, and which bits are momentary (press, then release on the next tic) */
static const unsigned char keys[INPUT_BITS] = {
    KEY_UPARROW,            /* SW0  forward */
    KEY_DOWNARROW,          /* SW1  back */
    KEY_LEFTARROW,          /* SW2  turn left (with SW8: strafe left) */
    KEY_RIGHTARROW,         /* SW3  turn right (with SW8: strafe right) */
    KEY_RSHIFT,             /* SW4  run */
    KEY_USE,                /* SW5  use / open */
    KEY_ENTER,              /* SW6  Enter (menu: select) */
    KEY_ESCAPE,             /* SW7  Escape (menu: open / back) */
    KEY_RALT,               /* SW8  strafe: turn keys move sideways */
    INPUT_NEXT_WEAPON_KEY,  /* SW9  next weapon */
    KEY_FIRE,               /* KEY0 fire */
};
#define MOMENTARY ((1u << 6) | (1u << 7) | (1u << 9))

#define QUEUE 32
static struct { unsigned char key, pressed; } queue[QUEUE];
static int head, count;
static uint32_t last;           /* inputs at the last sample */
static uint32_t release_next;   /* momentary keys pressed at the last sample */
static int sampled;             /* this tic's sample was taken: the next empty call returns 0 */

static void push(unsigned char key, int pressed)
{
    if (count < QUEUE) {
        queue[(head + count) % QUEUE].key = key;
        queue[(head + count) % QUEUE].pressed = (unsigned char)pressed;
        count++;
    }
}

static void sample(uint32_t inputs)
{
    for (int bit = 0; bit < INPUT_BITS; bit++)
        if (release_next & (1u << bit))
            push(keys[bit], 0);
    release_next = 0;

    /* Releases first, then presses */
    uint32_t up = inputs & ~last, down = last & ~inputs & ~MOMENTARY;
    for (int bit = 0; bit < INPUT_BITS; bit++)
        if (down & (1u << bit))
            push(keys[bit], 0);
    for (int bit = 0; bit < INPUT_BITS; bit++)
        if (up & (1u << bit)) {
            push(keys[bit], 1);
            if (MOMENTARY & (1u << bit))
                release_next |= 1u << bit;
        }
    last = inputs;
}

int input_get_key(uint32_t inputs, int *pressed, unsigned char *key)
{
    if (count == 0) {
        if (sampled) {              /* this tic's events are all out */
            sampled = 0;
            return 0;
        }
        sample(inputs & ((1u << INPUT_BITS) - 1));
        sampled = 1;
        if (count == 0) {
            sampled = 0;
            return 0;
        }
    }
    *key = queue[head].key;
    *pressed = queue[head].pressed;
    head = (head + 1) % QUEUE;
    count--;
    return 1;
}

unsigned char input_key_of_bit(int bit)
{
    return bit >= 0 && bit < INPUT_BITS ? keys[bit] : 0;
}
