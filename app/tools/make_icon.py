#!/usr/bin/env python3
"""Draws the Swift DM icon (blue rounded square, white down-arrow over a tray) as PNGs, no dependencies."""
import os, struct, sys, zlib


def png(path, size, pixels):
    raw = b"".join(b"\x00" + bytes(pixels[y * size * 4:(y + 1) * size * 4]) for y in range(size))
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    data = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)) \
        + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(data)


def inside_rrect(x, y, x0, y0, x1, y1, r):
    if x < x0 or x > x1 or y < y0 or y > y1:
        return False
    cx = min(max(x, x0 + r), x1 - r)
    cy = min(max(y, y0 + r), y1 - r)
    return (x - cx) ** 2 + (y - cy) ** 2 <= r * r


def shape(x, y, margin):
    """Returns (in_bg, in_glyph) for normalized coords 0..1."""
    m = margin
    bg = inside_rrect(x, y, m, m, 1 - m, 1 - m, 0.2237 * (1 - 2 * m))
    if not bg:
        return False, False
    # arrow shaft
    glyph = 0.44 <= x <= 0.56 and 0.20 <= y <= 0.52
    # arrow head (triangle pointing down)
    if not glyph and 0.40 <= y <= 0.66:
        half = (0.66 - y) / 0.26 * 0.20
        glyph = abs(x - 0.5) <= half
    # tray
    if not glyph:
        glyph = (0.24 <= x <= 0.76 and 0.72 <= y <= 0.80) or \
                ((0.24 <= x <= 0.32 or 0.68 <= x <= 0.76) and 0.60 <= y <= 0.80)
    return True, glyph


def render(size, margin):
    ss = 4 if size <= 256 else 2
    px = bytearray(size * size * 4)
    top, bot = (64, 132, 255), (30, 78, 216)
    for j in range(size):
        for i in range(size):
            a_bg = a_gl = 0
            for sy in range(ss):
                for sx in range(ss):
                    x = (i + (sx + 0.5) / ss) / size
                    y = (j + (sy + 0.5) / ss) / size
                    b, g = shape(x, y, margin)
                    a_bg += b
                    a_gl += g
            n = ss * ss
            t = j / size
            bgc = [round(top[k] + (bot[k] - top[k]) * t) for k in range(3)]
            if a_bg == 0:
                continue
            g = a_gl / a_bg
            col = [round(bgc[k] * (1 - g) + 255 * g) for k in range(3)]
            o = (j * size + i) * 4
            px[o:o + 4] = bytes(col + [round(255 * a_bg / n)])
    return px


def main(out_iconset, out_ext):
    os.makedirs(out_iconset, exist_ok=True)
    os.makedirs(out_ext, exist_ok=True)
    cache = {}
    def get(size, margin):
        if (size, margin) not in cache:
            cache[(size, margin)] = render(size, margin)
        return cache[(size, margin)]
    # macOS icons leave ~10% margin around the rounded square
    for base in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            s = base * scale
            name = f"icon_{base}x{base}{'@2x' if scale == 2 else ''}.png"
            png(os.path.join(out_iconset, name), s, get(s, 0.098))
    for s in (16, 48, 128):
        png(os.path.join(out_ext, f"icon{s}.png"), s, get(s, 0.0 if s == 16 else 0.04))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
