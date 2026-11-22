"""
Makes the initial image for the video mode A framebuffer (128x96, 12 bits per pixel).

Usage (from the repo folder):
  python src/tools/img2fb.py             test pattern
  python src/tools/img2fb.py photo.png   any image (needs: pip install pillow)

Output: mem/fb_test.hex, one pixel per line (RGB, 4 bits each), row by row.
"""
import sys
from pathlib import Path

W, H = 128, 96
OUT = Path(__file__).resolve().parents[2] / "mem" / "fb_test.hex"


def test_pattern():
    # top: 8 color bars, bottom: 16 gray levels, white border around everything
    bars = [(15, 15, 15), (15, 15, 0), (0, 15, 15), (0, 15, 0),
            (15, 0, 15), (15, 0, 0), (0, 0, 15), (0, 0, 0)]
    pixels = []
    for y in range(H):
        for x in range(W):
            if x == 0 or y == 0 or x == W - 1 or y == H - 1:
                c = (15, 15, 15)
            elif y < 64:
                c = bars[x // 16]
            else:
                g = x // 8
                c = (g, g, g)
            pixels.append(c)
    return pixels


def from_image(path):
    from PIL import Image
    img = Image.open(path).convert("RGB").resize((W, H))
    # keep the top 4 bits of each color, like the hardware does
    return [(r >> 4, g >> 4, b >> 4) for r, g, b in img.getdata()]


def main():
    pixels = from_image(sys.argv[1]) if len(sys.argv) > 1 else test_pattern()
    with open(OUT, "w") as f:
        for r, g, b in pixels:
            f.write(f"{r:X}{g:X}{b:X}\n")
    print(f"{OUT} ({W}x{H})")


if __name__ == "__main__":
    main()
