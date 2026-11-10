"""Convert the simulation's RGB PPM into a PNG using only the Python standard library."""
from pathlib import Path
import struct
import sys
import zlib

magic, dimensions, maximum, pixels = Path(sys.argv[1]).read_bytes().split(b"\n", 3)
width, height = map(int, dimensions.split())
if magic != b"P6" or maximum != b"255" or len(pixels) != width * height * 3:
    raise SystemExit("Unexpected simulation image format or truncated image")

def chunk(tag, payload):
    return (struct.pack(">I", len(payload)) + tag + payload
            + struct.pack(">I", zlib.crc32(tag + payload) & 0xffffffff))

stride = width * 3
scanlines = b"".join(b"\0" + pixels[y*stride:(y+1)*stride] for y in range(height))
png = b"\x89PNG\r\n\x1a\n"
png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(scanlines))
png += chunk(b"IEND", b"")
Path(sys.argv[2]).write_bytes(png)
