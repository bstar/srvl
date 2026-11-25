"""Inspect the actual pinned Himbaechel v6 binary timing table and design.

Packed offsets follow nextpnr's himbaechel/chipdb.h and common/kernel/relptr.h.
This reports cell-model presence; it does not prove complete path, I/O, hold,
clock-phase, CDC, analog or silicon coverage.
"""

import collections
import hashlib
import json
from pathlib import Path
import re
import struct
import sys

database, tool_source, netlist, output = map(Path, sys.argv[1:5])
blob = database.read_bytes()


def number(at):
    return struct.unpack_from("<i", blob, at)[0]


def pointer(at):
    result = at + number(at)
    assert 0 <= result < len(blob), "Invalid relative pointer"
    return result


def sequence(at):
    return pointer(at), struct.unpack_from("<I", blob, at + 4)[0]


def string(at):
    return blob[at:blob.index(0, at)].decode("utf-8")


root = pointer(0)
assert number(root) == 0x00CA7CA7 and number(root + 4) == 6, "Review changed chip database schema"
assert string(pointer(root + 16)) == "gowin" and string(pointer(root + 20)) == "GW2A-18C"
constids = tool_source / "himbaechel/uarch/gowin/constids.inc"
names = [""] + re.findall(r"^X\((.*)\)$", constids.read_text(), re.M)
ids = pointer(root + 76)
assert number(ids) == len(names), "ConstID source does not match the binary database"
extra, count = sequence(ids + 4)
names += [string(pointer(extra + 4 * i)) for i in range(count)]
grades, count = sequence(root + 68)
grade = next(grades + 32 * i for i in range(count) if names[number(grades + 32 * i)] == "C8/I7")
cells, count = sequence(grade + 20)
models = {}
for i in range(count):
    at = cells + 12 * i
    pins, pin_count = sequence(at + 4)
    models[names[number(at)]] = {
        "pins": pin_count,
        "combinational_arcs": sum(sequence(pins + 24 * p + 8)[1] for p in range(pin_count)),
        "register_arcs": sum(sequence(pins + 24 * p + 16)[1] for p in range(pin_count)),
    }
modules = json.loads(netlist.read_text())["modules"]
design = modules["lynx_tang_board"] if "lynx_tang_board" in modules else modules["top"]
counts = collections.Counter(c["type"] for c in design["cells"].values())
missing = {kind: count for kind, count in sorted(counts.items()) if kind not in models and kind != "$scopeinfo"}
fabric = {kind for kind in counts if kind.startswith(("LUT", "DFF", "MUX2_LUT")) or kind == "ALU"}
missing_fabric = sorted(fabric - models.keys())
assert not missing_fabric, f"Fabric types without timing models: {missing_fabric}"
review_files = ["himbaechel/chipdb.h", "common/kernel/relptr.h", "himbaechel/arch.cc",
                "himbaechel/uarch/gowin/gowin_arch_gen.py", "common/kernel/sdc.cc",
                "himbaechel/uarch/gowin/constids.inc"]
result = {
    "scope": "actual pinned binary cell-timing model coverage, not complete path or board timing signoff",
    "part": "GW2AR-LV18QN88C8/I7", "speed_grade": "C8/I7", "database_version": 6,
    "database_sha256": hashlib.sha256(blob).hexdigest(),
    "reviewed_tool_source_sha256": {p: hashlib.sha256((tool_source / p).read_bytes()).hexdigest() for p in review_files},
    "available_cell_models": models, "mapped_cell_counts": dict(counts),
    "cell_types_without_models": missing, "missing_fabric_models": missing_fabric,
    "fabric_model_presence_passed": True,
    "unsupported_or_unqualified": ["DSP delay arcs", "OSER10 and serializer phase", "PLL/clock phase and jitter",
                                  "external SDRAM setup/hold and read capture", "external I/O budgets",
                                  "CDC/metastability and reset recovery", "complete hold/path coverage"],
    "sdc_limitations": {"set_false_path": "parsed but not applied", "input_output_delay_commands": "unsupported by pinned generic parser"},
    "complete_board_timing_signoff": False, "physical_testing": False,
}
output.write_text(json.dumps(result, indent=2) + "\n")
print("PASS: fabric cells have binary database models; unqualified types:", missing)
