"""DOOM-6: compare a frame from the simulation with the PC reference, and/or save it as PNG.

    python src/tools/frame_compare.py <frame.ppm> [<reference.ppm>] [--png <out.png>] [--scale N]

<frame.ppm>: framebuffer B saved by the Verilator harness (+snap_pc / +ppm_b): P3, 4 bits per
color (max 15), what video mode B shows. <reference.ppm>: a frame of the host build
(make -C src/doom host-run): P6, 8 bits per color. Mode B's palette keeps the upper 4 bits of
each color (rtl/palette.v), so the reference is compared at 4 bits: color >> 4.
Prints "MATCH" or how many pixels differ (and the first one); exit code 1 if any differs.
--png writes <frame.ppm> as a PNG (colors scaled to 8 bits, pixels repeated --scale times,
default 2), for the report. No libraries needed.
"""
import argparse
import struct
import sys
import zlib


def read_ppm(path):
    """Returns (width, height, maxval, [r, g, b, r, g, b, ...])."""
    data = open(path, "rb").read()
    fields, pos = [], 0
    while len(fields) < 4:                      # magic, width, height, maxval
        while data[pos:pos + 1].isspace():
            pos += 1
        if data[pos:pos + 1] == b"#":
            while data[pos:pos + 1] not in (b"\n", b""):
                pos += 1
            continue
        start = pos
        while pos < len(data) and not data[pos:pos + 1].isspace():
            pos += 1
        fields.append(data[start:pos].decode())
    magic, w, h, maxval = fields[0], int(fields[1]), int(fields[2]), int(fields[3])
    if magic == "P6":
        pixels = list(data[pos + 1:pos + 1 + 3 * w * h])
    elif magic == "P3":
        pixels = [int(v) for v in data[pos:].split()][:3 * w * h]
    else:
        sys.exit(f"Error: {path} is not a P3/P6 PPM")
    if len(pixels) != 3 * w * h:
        sys.exit(f"Error: {path} is truncated")
    return w, h, maxval, pixels


def to_4bit(maxval, pixels):
    if maxval == 15:
        return pixels
    if maxval == 255:
        return [v >> 4 for v in pixels]
    sys.exit(f"Error: unexpected max value {maxval}")


def write_png(path, w, h, maxval, pixels, scale):
    rows = []
    for y in range(h):
        row = bytearray()
        for x in range(w):
            i = 3 * (y * w + x)
            rgb = bytes(pixels[i + k] * 255 // maxval for k in range(3))
            row += rgb * scale
        rows.append(b"\x00" + bytes(row))
    raw = b"".join(r for r in rows for _ in range(scale))

    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", w * scale, h * scale, 8, 2, 0, 0, 0)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def main():
    ap = argparse.ArgumentParser(description="Compare a simulated mode B frame with the PC reference (DOOM-6)")
    ap.add_argument("frame")
    ap.add_argument("reference", nargs="?")
    ap.add_argument("--png", help="also save the frame as PNG")
    ap.add_argument("--scale", type=int, default=2)
    args = ap.parse_args()

    w, h, maxval, pixels = read_ppm(args.frame)
    if args.png:
        write_png(args.png, w, h, maxval, pixels, args.scale)
        print(f"{args.png}: {w * args.scale}x{h * args.scale}")
    if not args.reference:
        return
    rw, rh, rmax, ref = read_ppm(args.reference)
    if (w, h) != (rw, rh):
        sys.exit(f"Error: sizes differ: {w}x{h} vs {rw}x{rh}")
    a, b = to_4bit(maxval, pixels), to_4bit(rmax, ref)
    bad = [i for i in range(w * h) if a[3 * i:3 * i + 3] != b[3 * i:3 * i + 3]]
    if not bad:
        print(f"MATCH: {args.frame} = {args.reference} at 4 bits per color ({w}x{h})")
        return
    i = bad[0]
    print(f"DIFFER: {len(bad)} of {w * h} pixels; first at ({i % w}, {i // w}): "
          f"{a[3 * i:3 * i + 3]} vs {b[3 * i:3 * i + 3]}")
    sys.exit(1)


if __name__ == "__main__":
    main()
