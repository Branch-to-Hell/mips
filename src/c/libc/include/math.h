/* Minimal C library for our MIPS (TC-10): math.h. Soft float (-msoft-float): only what Doom
   calls, the rest of the operations come from libgcc. */
#ifndef _MATH_H
#define _MATH_H

double fabs(double x);
float fabsf(float x);

#endif
