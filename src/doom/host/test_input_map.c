/* DOOM-8: checks of input_map.c's event logic on the PC (make -C src/doom input-test).
   Each "tic" calls input_get_key until it returns 0, like doomgeneric's I_GetEvent. */
#include <stdio.h>
#include <string.h>

#include "input_map.h"
#include "doomkeys.h"

static int failures;
static char got[256];

/* One tic with these inputs: the events as text, e.g. "+ad -0d" (+ = down, - = up) */
static const char *tic(uint32_t inputs)
{
    int pressed, n = 0;
    unsigned char key;
    got[0] = 0;
    while (input_get_key(inputs, &pressed, &key) && n < 30) {
        char one[8];
        snprintf(one, sizeof one, "%s%c%02x", n ? " " : "", pressed ? '+' : '-', key);
        strcat(got, one);
        n++;
    }
    return got;
}

static void expect(const char *what, uint32_t inputs, const char *events)
{
    const char *g = tic(inputs);
    if (strcmp(g, events)) {
        printf("FAIL %s: got \"%s\", expected \"%s\"\n", what, g, events);
        failures++;
    }
}

int main(void)
{
    expect("nothing", 0, "");
    expect("SW0 up: forward down", 0x001, "+ad");
    expect("SW0 held: nothing more", 0x001, "");
    expect("SW0 down: forward up", 0x000, "-ad");
    expect("SW6 up: Enter down", 0x040, "+0d");
    expect("SW6 still up: Enter up, no repeat", 0x040, "-0d");
    expect("SW6 held: nothing", 0x040, "");
    expect("SW6 down: nothing", 0x000, "");
    expect("SW7 up: Escape down", 0x080, "+1b");
    expect("SW7 down: Escape up (next tic)", 0x000, "-1b");
    expect("KEY0: fire down", INPUT_KEY0, "+a3");
    expect("KEY0 released: fire up", 0, "-a3");
    expect("SW2+SW8 together", 0x104, "+ac +b8");
    expect("both down", 0x000, "-ac -b8");
    expect("SW9: next weapon down", 0x200, "+5d");
    expect("SW9: next weapon up", 0x200, "-5d");
    expect("SW9 down, SW4 up: run down", 0x010, "+b6");
    expect("SW4 down", 0x000, "-b6");
    expect("SW5 use", 0x020, "+a2");
    expect("SW5 off, SW3 on", 0x008, "-a2 +ae");
    expect("all off", 0x000, "-ae");
    expect("SW1 back", 0x002, "+af");
    expect("SW1 off", 0x000, "-af");
    expect("bits above SW9/KEY0 ignored", 0xFFFFF800u, "");

    if (failures == 0)
        printf("PASS: input_map, 24 tics\n");
    return failures != 0;
}
