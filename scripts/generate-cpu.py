"""Build the pinned R65C02 VHDL core into Verilog without editing upstream inputs."""
from pathlib import Path
import os
import shutil
import subprocess
import sys

source, patch, dest = (Path(arg).resolve() for arg in sys.argv[1:])
dest.mkdir(parents=True)
sources = dest / "sources"
sources.mkdir()
files = ["regbank_axy.vhd", "reg_sp.vhd", "reg_pc.vhd", "fsm_intnmi.vhd",
         "fsm_execution_unit.vhd", "core.vhd"]
for name in files:
    # Normalize CRLF before applying the explicit, reviewable correction patch.
    (sources / name).write_text((source / "rtl/vhdl" / name).read_text())
shutil.copy(source / "copyright_GNU_V3.txt", dest / "LICENSE.txt")
shutil.copy(patch, dest / patch.name)
os.chdir(sources)
with patch.open("rb") as patch_input:
    subprocess.run(["patch", "-p1", "--batch", "--forward"], stdin=patch_input, check=True)
subprocess.run(["ghdl", "-a", "--std=08", "-fsynopsys", "--work=r65c02_tc", *files], check=True)
with (dest / "cpu.v").open("w") as output:
    output.write("// SPDX-License-Identifier: GPL-3.0-or-later\n"
                 "// Generated from Jens Gutschmidt's R65C02 core.\n"
                 "// Original and modified VHDL, correction patch and license accompany this file.\n")
    output.flush()
    subprocess.run(["ghdl", "--synth", "--std=08", "-fsynopsys",
                    "--work=r65c02_tc", "--out=verilog", "core"], stdout=output, check=True)
# The analysis database embeds build paths; only source and generated HDL belong
# in the reusable output.
for database in sources.glob("*.cf"):
    database.unlink()
