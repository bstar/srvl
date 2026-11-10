"""Assemble the original prototype ROM and emit deterministic memory data."""
from pathlib import Path
import shutil
import subprocess
import sys

firmware, destination = (Path(arg).resolve() for arg in sys.argv[1:])
destination.mkdir(parents=True)
subprocess.run(["ca65", "-I", str(firmware), "-o", "courier.o",
                "-l", str(destination / "courier.lst"), str(firmware / "courier.s")], check=True)
subprocess.run(["ld65", "-C", str(firmware / "rom.cfg"), "-o", str(destination / "courier.bin"),
                "-m", str(destination / "courier.map"), "-Ln", str(destination / "courier.labels"),
                "courier.o"], check=True)
data = (destination / "courier.bin").read_bytes()
if len(data) != 32768 or data[-4:-2] != bytes([0, 128]):
    raise SystemExit("Unexpected original ROM size/reset vector")
(destination / "courier.hex").write_text("".join(f"{byte:02x}\n" for byte in data))
shutil.copytree(firmware, destination / "sources")
