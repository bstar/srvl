"""Generate original bitmap ROMs for the Circuit Courier prototype.

No external fonts, game graphics, or copyrighted console ROMs are used.
Font rows are eight bits; sprite rows pack sixteen two-bit pixels, leftmost first.
"""
from pathlib import Path
import argparse

GLYPHS = {
    "A": [14,17,17,31,17,17,17], "B": [30,17,17,30,17,17,30],
    "C": [14,17,16,16,16,17,14], "D": [30,17,17,17,17,17,30],
    "E": [31,16,16,30,16,16,31], "F": [31,16,16,30,16,16,16],
    "G": [14,17,16,23,17,17,15], "H": [17,17,17,31,17,17,17],
    "I": [14,4,4,4,4,4,14], "J": [7,2,2,2,18,18,12],
    "K": [17,18,20,24,20,18,17], "L": [16,16,16,16,16,16,31],
    "M": [17,27,21,21,17,17,17], "N": [17,25,21,19,17,17,17],
    "O": [14,17,17,17,17,17,14], "P": [30,17,17,30,16,16,16],
    "Q": [14,17,17,17,21,18,13], "R": [30,17,17,30,20,18,17],
    "S": [15,16,16,14,1,1,30], "T": [31,4,4,4,4,4,4],
    "U": [17,17,17,17,17,17,14], "V": [17,17,17,17,17,10,4],
    "W": [17,17,17,21,21,21,10], "X": [17,17,10,4,10,17,17],
    "Y": [17,17,10,4,4,4,4], "Z": [31,1,2,4,8,16,31],
    "0": [14,17,19,21,25,17,14], "1": [4,12,4,4,4,4,14],
    "2": [14,17,1,2,4,8,31], "3": [30,1,1,14,1,1,30],
    "4": [2,6,10,18,31,2,2], "5": [31,16,16,30,1,1,30],
    "6": [14,16,16,30,17,17,14], "7": [31,1,2,4,8,8,8],
    "8": [14,17,17,14,17,17,14], "9": [14,17,17,15,1,1,14],
    ":": [0,4,4,0,4,4,0], ".": [0,0,0,0,0,4,4],
    "-": [0,0,0,31,0,0,0], "+": [0,4,4,31,4,4,0],
    "/": [1,2,2,4,8,8,16], "!": [4,4,4,4,4,0,4],
    "?": [14,17,1,2,4,0,4], "=": [0,0,31,0,31,0,0],
    "<": [2,4,8,16,8,4,2], ">": [8,4,2,1,2,4,8],
    "(": [2,4,8,8,8,4,2], ")": [8,4,2,2,2,4,8],
}


def font_rows():
    rows = [0] * (256 * 8)
    for char, glyph in GLYPHS.items():
        for y, bits in enumerate(glyph):
            rows[ord(char) * 8 + y] = bits << 2
    # Small circuit-board tiles below the printable character range.
    rows[1*8:2*8] = [0,0,0,0,8,0,0,0]
    rows[2*8:3*8] = [255,129,129,153,153,129,129,255]
    rows[3*8:4*8] = [0,0,24,24,255,24,24,0]
    rows[4*8:5*8] = [0,0,0,0,255,0,0,0]
    rows[5*8:6*8] = [8] * 8
    rows[6*8:7*8] = [129,0,0,0,0,0,0,129]
    rows[7*8:8*8] = [0,0,8,12,254,12,8,0]
    rows[8*8:9*8] = [0,16,16,124,16,16,0,0]
    rows[9*8:10*8] = [255,129,189,165,165,189,129,255]  # Maze wall panels.
    return rows


def sprite_pixel(kind, x, y):
    frame = kind & 1
    if kind < 2:  # Courier drone: four rotors and a bright cockpit.
        if x == 2 and y == 7:  # Asymmetric navigation light also exercises H-flip.
            return 3
        for rx, ry in ((3,4), (12,4), (3,11), (12,11)):
            if (abs(x-rx) <= 2 and y == ry) if frame else (x == rx and abs(y-ry) <= 2):
                return 3
        if 4 <= x <= 11 and 2 <= y <= 13:
            if 5 <= x <= 10 and 3 <= y <= 12:
                return 3 if 6 <= x <= 9 and 5 <= y <= 6 else 2
            return 1
        if 1 <= x <= 14 and 7 <= y <= 8:
            return 2
    elif kind < 4:  # Sealed data packet with a cross-shaped stamp.
        y += frame
        if 3 <= x <= 12 and 2 <= y <= 13 and abs(2*x-15)+abs(2*y-15) <= 20:
            if x in (3,12) or y in (2,13):
                return 1
            return 3 if (x in (7,8) and 5 <= y <= 10) or (y in (7,8) and 5 <= x <= 10) else 2
    elif kind < 6:  # Security sentinel.
        distance = abs(2*x-15) + abs(2*y-15)
        if distance <= 14:
            if distance >= 12:
                return 1
            return 3 if (y == 6+frame and x in (5,6,9,10)) else 2
    else:  # Delivery dock; the second frame lights its inner contacts.
        if 2 <= x <= 13 and 1 <= y <= 14:
            if x in (2,3,12,13) or y in (1,2,13,14):
                return 3 if (x+y) % 4 == 0 else 2
            if frame and y in (5,10) and 6 <= x <= 9:
                return 3
    return 0


def write_assets(dest):
    dest.mkdir(parents=True, exist_ok=True)
    (dest / "font.hex").write_text("".join(f"{row:02x}\n" for row in font_rows()))
    sprites = []
    for kind in range(8):
        for y in range(16):
            sprites.append(sum(sprite_pixel(kind,x,y) << (2*x) for x in range(16)))
    (dest / "sprites.hex").write_text("".join(f"{row:08x}\n" for row in sprites))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path)
    write_assets(parser.parse_args().destination)
