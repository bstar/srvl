"""Represent small Gowin LUTs as equivalent physical LUT4s for timing coverage.

The pinned nextpnr database has LUT4 delay arcs but no LUT1/2/3 variants.
Constant padding and replicated truth tables preserve every original input case.
No registers, RAMs, DSPs, I/O or existing LUT4 cells are altered.
"""

import collections
import json
from pathlib import Path
import sys

input_path, output_path, evidence_path = map(Path, sys.argv[1:4])
top_name = sys.argv[4] if len(sys.argv) > 4 else "lynx_tang_board"
netlist = json.loads(input_path.read_text())
top = netlist["modules"][top_name]
changed = collections.Counter()
cases = 0
for cell in top["cells"].values():
    if cell["type"] not in {"LUT1", "LUT2", "LUT3"}:
        continue
    width = int(cell["type"][-1])
    init = cell["parameters"]["INIT"]
    assert len(init) == 1 << width and set(init) <= {"0", "1"}
    assert set(cell["connections"]) == {"F", *(f"I{i}" for i in range(width))}
    expanded = init * (16 // len(init))
    for value in range(1 << width):
        assert (int(init, 2) >> value) & 1 == (int(expanded, 2) >> value) & 1
        cases += 1
    changed[cell["type"]] += 1
    cell["type"] = "LUT4"
    cell["parameters"]["INIT"] = expanded
    for i in range(width, 4):
        cell["connections"][f"I{i}"] = ["0"]
        cell["port_directions"][f"I{i}"] = "input"
output_path.write_text(json.dumps(netlist, separators=(",", ":")) + "\n")
evidence = {"scope": "per-cell combinational equivalence of small-LUT to LUT4 normalization; no DSP/I/O timing qualification",
            "converted_cells": dict(changed), "exhaustive_original_input_cases": cases,
            "unused_inputs": "constant zero", "truth_table_equivalence_passed": True}
evidence_path.write_text(json.dumps(evidence, indent=2) + "\n")
print(f"PASS: normalized {sum(changed.values())} LUTs; {cases} exhaustive original input cases")
