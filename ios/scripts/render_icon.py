#!/usr/bin/env python3
"""Rasterise icon.svg to a 1024x1024 PNG app icon, with no image libraries.

The mark is nothing but round-capped polylines on a rounded rect, so stroking
it is stamping an anti-aliased disc along each segment and keeping the maximum
coverage per pixel (max, not sum, so overlapping stamps don't darken seams).
"""
import re
import struct
import sys
import zlib

SIZE = 1024
SCALE = SIZE / 512.0
CORNER = 110 * SCALE

BG = (0x14, 0x18, 0x24)
INK = (0xE2, 0x3B, 0x3B)

RAYS = "M78 78L590.1 168.3 M78 78L528.3 338.0 M78 78L412.2 476.3 M78 78L255.9 566.6 M78 78L96.1 597.7"

GRID = (
    "M215.9 102.3L211.6 105.6L207.4 108.7L203.7 111.7L200.5 114.7L198.1 117.8L196.4 121.1L195.5 124.7"
    "L195.4 128.6L195.9 133.0L196.9 137.7L198.0 142.7L199.2 148.0 "
    "M199.2 148.0L194.1 149.6L189.1 151.1L184.6 152.6L180.6 154.4L177.2 156.4L174.5 159.0L172.5 162.1"
    "L171.0 165.8L170.0 170.0L169.3 174.7L168.7 179.9L168.0 185.2 "
    "M168.0 185.2L162.6 185.0L157.4 184.7L152.6 184.6L148.3 184.8L144.4 185.6L141.0 187.1L138.0 189.3"
    "L135.4 192.3L133.0 195.9L130.7 200.1L128.4 204.7L125.9 209.6 "
    "M125.9 209.6L121.3 207.3L116.9 205.2L112.8 203.4L108.9 202.1L105.4 201.5L102.0 201.7L98.9 202.7"
    "L95.8 204.6L92.7 207.3L89.6 210.5L86.3 214.1L82.9 217.9 "
    "M324.2 121.4L316.5 127.2L309.1 132.8L302.4 138.1L296.8 143.5L292.4 149.0L289.4 155.0L287.9 161.4"
    "L287.7 168.4L288.6 176.2L290.2 184.6L292.4 193.6L294.5 203.0 "
    "M294.5 203.0L285.3 205.8L276.4 208.5L268.3 211.3L261.2 214.4L255.2 218.1L250.4 222.6L246.7 228.1"
    "L244.1 234.7L242.3 242.3L241.0 250.8L239.9 259.9L238.7 269.5 "
    "M238.7 269.5L229.0 269.0L219.8 268.5L211.3 268.3L203.5 268.8L196.6 270.2L190.5 272.9L185.2 276.8"
    "L180.5 282.1L176.2 288.6L172.1 296.1L167.9 304.3L163.5 312.9 "
    "M163.5 312.9L155.3 308.9L147.4 305.1L140.1 301.9L133.2 299.6L126.9 298.5L120.9 298.9L115.3 300.8"
    "L109.8 304.1L104.3 308.8L98.7 314.6L92.9 321.1L86.7 327.8 "
    "M432.5 140.5L421.4 148.9L410.8 156.9L401.1 164.6L393.0 172.3L386.7 180.3L382.5 188.8L380.2 198.1"
    "L379.9 208.2L381.2 219.4L383.6 231.5L386.7 244.4L389.8 258.0 "
    "M389.8 258.0L376.5 262.1L363.7 265.9L352.0 269.9L341.8 274.4L333.1 279.7L326.2 286.3L321.0 294.2"
    "L317.2 303.7L314.6 314.6L312.7 326.8L311.1 340.0L309.4 353.8 "
    "M309.4 353.8L295.5 353.1L282.2 352.3L269.9 352.0L258.7 352.7L248.7 354.8L240.0 358.6L232.4 364.3"
    "L225.6 371.8L219.4 381.2L213.5 392.0L207.5 403.9L201.1 416.3 "
    "M201.1 416.3L189.3 410.6L178.0 405.1L167.4 400.4L157.5 397.1L148.4 395.5L139.8 396.0L131.7 398.8"
    "L123.8 403.6L115.9 410.4L107.8 418.7L99.4 428.0L90.6 437.8 "
    "M540.9 159.6L526.4 170.6L512.5 181.0L499.9 191.0L489.3 201.1L481.0 211.6L475.5 222.7L472.6 234.8"
    "L472.2 248.0L473.8 262.6L477.0 278.4L481.0 295.3L485.0 313.0 "
    "M485.0 313.0L467.7 318.4L451.0 323.4L435.8 328.5L422.3 334.4L411.1 341.4L402.0 349.9L395.2 360.3"
    "L390.3 372.6L386.8 386.8L384.4 402.8L382.4 420.0L380.1 438.0 "
    "M380.1 438.0L362.0 437.1L344.6 436.1L328.5 435.8L313.9 436.7L300.9 439.4L289.5 444.3L279.5 451.7"
    "L270.7 461.6L262.6 473.8L254.8 488.0L247.0 503.5L238.7 519.7 "
    "M238.7 519.7L223.3 512.2L208.5 505.0L194.7 498.9L181.9 494.5L169.9 492.5L158.7 493.2L148.1 496.8"
    "L137.7 503.1L127.4 512.0L116.9 522.8L106.0 535.0L94.4 547.7"
)


def subpaths(d):
    """`M x y L x y L x y` → lists of scaled points."""
    out = []
    for chunk in d.split("M"):
        chunk = chunk.strip()
        if not chunk:
            continue
        pts = []
        for pair in chunk.split("L"):
            nums = re.findall(r"-?\d+(?:\.\d+)?", pair)
            if len(nums) >= 2:
                pts.append((float(nums[0]) * SCALE, float(nums[1]) * SCALE))
        if len(pts) >= 2:
            out.append(pts)
    return out


def disc_template(radius):
    """(dx, dy, coverage) offsets for one anti-aliased dot."""
    r = int(radius) + 2
    cells = []
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            d = (dx * dx + dy * dy) ** 0.5
            cover = radius + 0.5 - d
            if cover <= 0:
                continue
            cells.append((dx, dy, min(1.0, cover)))
    return cells


def stroke(coverage, paths, width):
    radius = width * SCALE / 2.0
    template = disc_template(radius)
    for points in paths:
        for i in range(len(points) - 1):
            x0, y0 = points[i]
            x1, y1 = points[i + 1]
            length = ((x1 - x0) ** 2 + (y1 - y0) ** 2) ** 0.5
            steps = max(1, int(length))
            for s in range(steps + 1):
                t = s / steps
                cx = x0 + (x1 - x0) * t
                cy = y0 + (y1 - y0) * t
                bx, by = int(cx), int(cy)
                for dx, dy, cover in template:
                    px, py = bx + dx, by + dy
                    if 0 <= px < SIZE and 0 <= py < SIZE:
                        idx = py * SIZE + px
                        value = int(cover * 255)
                        if value > coverage[idx]:
                            coverage[idx] = value


def rounded_rect_mask():
    """1 inside the rounded rect, 0 outside — the SVG's clip-path."""
    mask = bytearray(SIZE * SIZE)
    r = CORNER
    for y in range(SIZE):
        for x in range(SIZE):
            cx = min(max(x + 0.5, r), SIZE - r)
            cy = min(max(y + 0.5, r), SIZE - r)
            dx, dy = x + 0.5 - cx, y + 0.5 - cy
            inside = (dx * dx + dy * dy) <= r * r
            mask[y * SIZE + x] = 255 if inside else 0
    return mask


def write_png(path, pixels):
    raw = bytearray()
    stride = SIZE * 3
    for y in range(SIZE):
        raw.append(0)
        raw.extend(pixels[y * stride:(y + 1) * stride])

    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", header)
           + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
           + chunk(b"IEND", b""))
    with open(path, "wb") as handle:
        handle.write(png)


def main(out):
    coverage = bytearray(SIZE * SIZE)
    stroke(coverage, subpaths(RAYS), 13)
    stroke(coverage, subpaths(GRID), 11)
    mask = rounded_rect_mask()

    pixels = bytearray(SIZE * SIZE * 3)
    for i in range(SIZE * SIZE):
        if mask[i] == 0:
            # iOS icons must be opaque squares — the system applies its own
            # corner mask. So the corners the SVG left transparent get the
            # background colour, and the mask's only remaining job is clipping
            # the strokes, exactly as `clip-path` did.
            r, g, b = BG
        else:
            a = coverage[i] / 255.0
            r = int(BG[0] + (INK[0] - BG[0]) * a)
            g = int(BG[1] + (INK[1] - BG[1]) * a)
            b = int(BG[2] + (INK[2] - BG[2]) * a)
        pixels[i * 3] = r
        pixels[i * 3 + 1] = g
        pixels[i * 3 + 2] = b
    write_png(out, pixels)
    print("wrote", out)


if __name__ == "__main__":
    main(sys.argv[1])
