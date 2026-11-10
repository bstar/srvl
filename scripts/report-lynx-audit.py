"""Report measured console cells and stock-wrapper memory without claiming fit."""
from collections import Counter
from pathlib import Path
import json
import re
import sys

source, netlist, target, output = map(Path, sys.argv[1:])
board = json.loads(target.read_text())
design = json.loads(netlist.read_text())
console = design["modules"]["lynx_audit"]
cells = Counter(cell["type"] for cell in console["cells"].values() if cell["type"] != "$scopeinfo")
unmapped = [name for name in cells if name.startswith("$")]
if unmapped:
    raise SystemExit(f"Unmapped internal cells: {unmapped}")
sv = (source / "AtariLynx.sv").read_text()
buffers = re.findall(r"reg\s*\[(\d+):0\]\s+(vram\d+)\[(\d+)\]", sv)
assert len(buffers) == 3, "Re-audit upstream framebuffer declarations"
buffer_bits = sum((int(width) + 1) * int(depth) for width, _, depth in buffers)
ram_source = (source / "rtl/memorymux.vhd").read_text().split("iram:", 1)[1]
ram_parameters = re.search(r"addr_width\s*=>\s*(\d+),\s*data_width\s*=>\s*(\d+)", ram_source)
assert ram_parameters, "Re-audit upstream work RAM"
ram_bits = (2 ** int(ram_parameters[1])) * int(ram_parameters[2])
lut_cells = sum(count for name, count in cells.items() if re.fullmatch(r"LUT[1-4]", name))
report = {
    "scope": "adapted baseline LynxTop only; not a complete board fit or compatibility certification",
    "upstream_revision": "3708e457e413aa7a33f8bec8fcd79eba45ce4702",
    "target": board,
    "measured_cells": dict(sorted(cells.items())),
    "lut1_to_lut4_cells": lut_cells,
    "alu_cells": cells["ALU"],
    "lut_plus_alu_estimate": lut_cells + cells["ALU"],
    "register_cells": sum(n for name, n in cells.items() if name.startswith("DFF")),
    "latch_cells": sum(n for name, n in cells.items() if name.startswith("DL")),
    "stock_memory": {
        "work_ram_bytes": ram_bits // 8,
        "three_rgb444_buffers_bytes": buffer_bits // 8,
        "minimum_combined_bytes": (ram_bits + buffer_bits) // 8,
        "tang_bsram_bytes": board["bsram_blocks"] * board["bsram_bits_per_block"] // 8,
        "fits_raw_internal_capacity": ram_bits + buffer_bits <= board["bsram_blocks"] * board["bsram_bits_per_block"],
        "single_buffer_bytes": buffer_bits // 8 // len(buffers),
        "double_buffer_16bit_sdram_bytes": 160 * 102 * 2 * 2,
    },
    "excluded": ["framebuffers", "SDRAM controller", "HDMI/LCD output", "game loader",
                 "physical inputs", "PLL and clock-generator setup", "rewind", "save states", "cheats", "FPS overlay"],
    "physical_timing_verified": False,
    "commercial_games_tested": 0,
}
output.write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps({key: report[key] for key in ("lut1_to_lut4_cells", "alu_cells", "register_cells", "latch_cells", "stock_memory")}, indent=2))
