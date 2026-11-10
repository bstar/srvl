"""Register-boundary harness for core-only placement/timing, never a game image.

Preserve every already-mapped console cell. Replace wide virtual ports with
serially loaded input registers and registered/output-shift capture. These four
physical pins are a tool harness; no programming image is generated.
"""
from pathlib import Path
import json
import sys

source, output = map(Path, sys.argv[1:])
design = json.loads(source.read_text())
top = design["modules"]["lynx_audit"]
bits = [bit for wire in top["netnames"].values() for bit in wire["bits"] if isinstance(bit, int)]
next_bit = max(bits) + 1
def net():
    global next_bit
    result = next_bit
    next_bit += 1
    top["netnames"][f"audit_net_{result}"] = {"hide_name": 0, "bits": [result], "attributes": {}}
    return result

cells = top["cells"]
before = len(cells)
def cell(name, kind, connections, directions, parameters=None):
    assert name not in cells
    cells[name] = {"hide_name": 0, "type": kind, "parameters": parameters or {},
                   "attributes": {"keep": "1"}, "port_directions": directions,
                   "connections": {key: [value] for key, value in connections.items()}}

ports = {}
def input_port(name, destination):
    pad = net()
    ports[name] = {"direction": "input", "bits": [pad]}
    cell("audit_" + name + "_ibuf", "IBUF", {"I": pad, "O": destination}, {"I": "input", "O": "output"})

clock = top["ports"]["clk"]["bits"][0]
serial_in, capture = net(), net()
input_port("probe_clock", clock)
input_port("probe_serial_in", serial_in)
input_port("probe_capture", capture)
last = serial_in
inputs = 0
outputs = []
for name, port in top["ports"].items():
    if name == "clk":
        continue
    if port["direction"] == "input":
        for bit in port["bits"]:
            if not isinstance(bit, int):
                continue
            cell(f"audit_in_{inputs}", "DFF", {"CLK": clock, "D": last, "Q": bit},
                 {"CLK": "input", "D": "input", "Q": "output"})
            last = bit
            inputs += 1
    elif port["direction"] == "output":
        outputs.extend(port["bits"])
    else:
        raise SystemExit("Unexpected bidirectional core port")
for index, bit in enumerate(outputs):
    mux, q = net(), net()
    # LUT3 truth table: I2=capture ? I1=core output : I0=previous shift bit.
    cell(f"audit_mux_{index}", "LUT3", {"I0": last, "I1": bit, "I2": capture, "F": mux},
         {"I0": "input", "I1": "input", "I2": "input", "F": "output"}, {"INIT": "11001010"})
    cell(f"audit_out_{index}", "DFF", {"CLK": clock, "D": mux, "Q": q},
         {"CLK": "input", "D": "input", "Q": "output"})
    last = q
pad = net()
ports["probe_serial_out"] = {"direction": "output", "bits": [pad]}
cell("audit_output_obuf", "OBUF", {"I": last, "O": pad}, {"I": "input", "O": "output"})
top["ports"] = ports
output.write_text(json.dumps(design) + "\n")
output.with_suffix(".scope.json").write_text(json.dumps({
    "scope": "registered core-only route/timing probe; not a playable port or board timing signoff",
    "original_core_cells": before,
    "added_cells": len(cells) - before,
    "input_registers": inputs, "output_registers": len(outputs),
    "clock_mhz": 64,
    "omitted": ["SDRAM controller", "loader", "framebuffers", "HDMI/LCD", "audio transport", "real board clock setup"],
}, indent=2) + "\n")
