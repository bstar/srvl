"""Constraints for the enhanced-skeleton bench top from the reviewed pin manifest.

Every top-level bit must be assigned from hardware/boards/tang_nano20k/pins.json;
manifest entries for ports this top does not have (UART, audio) are skipped.
Clock targets are frequencies only: no phase relationship, I/O timing or
physical acceptance is established.
"""

import json
from pathlib import Path
import sys

TOP = "cb_enhanced_tang_board"
CLOCK_NETS = {"clocks.sys_clk": 64000000, "clocks.sdram_clk": 64000000, "clocks.serial_clk": 126000000,
              "clocks.pixel_clk": 25200000, "memory_clk": 8000000}
netlist, manifest, out = map(Path, sys.argv[1:4])
design = json.loads(netlist.read_text())["modules"][TOP]
config = json.loads(manifest.read_text())
out.mkdir(parents=True, exist_ok=True)
assigned, pads, constraints, clocks = {}, {}, [], []
for entry in config["ports"]:
    pairs = [(entry["port"], entry["pins"])]
    if "negative_port" in entry:
        pairs.append((entry["negative_port"], entry["negative_pins"]))
    if entry["port"] not in design["ports"]:
        continue
    attributes = [f'IO_TYPE={entry.get("io_type", config["io_type"])}', f'BANK_VCCIO={config["bank_vccio"]}',
                  f'PULL_MODE={entry.get("pull", "NONE")}']
    if entry["direction"] != "input":
        attributes.append(f'DRIVE={entry.get("drive", 8)}')
    for name, pins in pairs:
        port = design["ports"][name]
        assert port["direction"] == entry["direction"] and len(port["bits"]) == len(pins), f"Port mismatch: {name}"
        for index, pad in enumerate(pins):
            bit = name if len(pins) == 1 else f"{name}[{index}]"
            assert bit not in assigned and pad not in pads, f"Duplicate assignment: {bit} / {pad}"
            assigned[bit], pads[pad] = pad, bit
            constraints += [f'IO_LOC "{bit}" {pad};', f'IO_PORT "{bit}" {" ".join(attributes)};']
    if "reference_hz" in entry:
        clocks.append((entry["port"], entry["reference_hz"], "get_ports"))
expected = {name if len(port["bits"]) == 1 else f"{name}[{i}]" for name, port in design["ports"].items()
            for i in range(len(port["bits"]))}
assert set(assigned) == expected, f"Top-level coverage mismatch: {set(assigned) ^ expected}"
divider = design["cells"]["cpu_divider"]
assert divider["type"] == "CLKDIV" and divider["parameters"]["DIV_MODE"] == "8"
assert divider["connections"]["HCLKIN"] == design["netnames"]["clocks.sys_clk"]["bits"]
for name, hz in CLOCK_NETS.items():
    assert name in design["netnames"], f"Missing clock net: {name}"
    clocks.append((name, hz, "get_nets"))
(out / "board.cst").write_text("// Generated from the reviewed pin manifest; physical acceptance remains open.\n"
                               + "\n".join(constraints) + "\n")
(out / "board.sdc").write_text("# Clock frequency targets only.\n" + "\n".join(
    f"create_clock -period {1e9 / hz:.12f} [{selector} {{{name}}}]" for name, hz, selector in clocks) + "\n")
(out / "evidence.json").write_text(json.dumps({
    "scope": "all top-level bits of the enhanced skeleton assigned from the reviewed manifest; frequency targets only",
    "covered_top_level_bits": len(assigned), "clock_targets_hz": {name: hz for name, hz, _ in clocks},
    "physical_testing": False, "passed": True}, indent=2) + "\n")
print(f"PASS: {len(assigned)} top-level bits, {len(clocks)} clock targets")
