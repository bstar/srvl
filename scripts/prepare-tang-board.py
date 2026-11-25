"""Generate reviewed bench constraints; reject missing/duplicate top-level pins.

This establishes constraint coverage and clock targets, not board electrical or
external memory timing acceptance. Both differential pins are named explicitly:
the pinned CST parser's pair shorthand cannot infer a vector's negative name.
"""

import argparse
import json
from pathlib import Path
import re


def prepare(netlist, manifest, out):
    design = json.loads(netlist.read_text())["modules"]["lynx_tang_board"]
    config = json.loads(manifest.read_text())
    out.mkdir(parents=True, exist_ok=True)
    assigned, pads, constraints, clocks = {}, {}, [], []

    def expand(name, pins, direction):
        port = design["ports"][name]
        assert port["direction"] == direction, f"Direction mismatch: {name}"
        assert len(port["bits"]) == len(pins), f"Pin count mismatch: {name}"
        assert not port.get("upto", 0) and not port.get("offset", 0), f"Unsupported indexing: {name}"
        names = [name] if len(pins) == 1 else [f"{name}[{i}]" for i in range(len(pins))]
        for bit, pad in zip(names, pins):
            assert re.fullmatch(r"[0-9]+|IO[LR][0-9]+[AB]", pad), f"Invalid pad: {pad}"
            assert bit not in assigned, f"Port assigned twice: {bit}"
            assert pad not in pads, f"Pad assigned twice: {pad}"
            assigned[bit], pads[pad] = pad, bit
        return names

    covered = set()
    for entry in config["ports"]:
        name, pins = entry["port"], entry["pins"]
        assert name not in covered, f"Port appears twice: {name}"
        names = expand(name, pins, entry["direction"])
        covered.add(name)
        negative = entry.get("negative_pins")
        negative_names = []
        if negative:
            neg_name = entry["negative_port"]
            assert neg_name not in covered and len(negative) == len(pins)
            negative_names = expand(neg_name, negative, entry["direction"])
            covered.add(neg_name)
        for i, bit in enumerate(names):
            attrs = [f'IO_TYPE={entry.get("io_type", config["io_type"])}', f'BANK_VCCIO={config["bank_vccio"]}',
                     f'PULL_MODE={entry.get("pull", "NONE")}']
            if entry["direction"] != "input":
                attrs.append(f'DRIVE={entry.get("drive", 8)}')
            locations = [(bit, pins[i])]
            if negative:
                locations.append((negative_names[i], negative[i]))
            for named_bit, pad in locations:
                constraints.append(f'IO_LOC "{named_bit}" {pad};')
                constraints.append(f'IO_PORT "{named_bit}" {" ".join(attrs)};')
        if "reference_hz" in entry:
            assert len(names) == 1 and entry["direction"] == "input"
            clocks.append((name, entry["reference_hz"], "get_ports"))
    assert covered == set(design["ports"]), f'Top-level coverage mismatch: {covered ^ set(design["ports"])}'
    required_references = {"sys_ref": 64000000, "video_ref": 25200000, "audio_ref": 12288000}
    assert {name: hz for name, hz, _ in clocks} == required_references, "Reference profile differs from the board architecture"

    # Check the frequency targets against the actual mapped primitive graph.
    # This is parameter/wiring validation, not PLL phase or jitter simulation.
    primitive_clocks = {}
    for cell_name, reference, target in [("clocks.system_pll", "sys_ref", 64000000),
                                         ("clocks.video_pll", "video_ref", 126000000)]:
        cell = design["cells"][cell_name]
        p = cell["parameters"]
        assert cell["type"] == "rPLL" and p["CLKFB_SEL"] == "internal"
        assert all(p[k] == "false" for k in ["DYN_IDIV_SEL", "DYN_FBDIV_SEL", "DYN_ODIV_SEL", "DYN_DA_EN"])
        assert float(p["FCLKIN"]) * 1000000 == required_references[reference]
        output = required_references[reference] * (int(p["FBDIV_SEL"], 2) + 1) / (int(p["IDIV_SEL"], 2) + 1)
        assert output == target, f"PLL ratio differs from timing target: {cell_name}"
        assert any(c["type"] == "IBUF" and c["connections"]["I"] == design["ports"][reference]["bits"]
                   and c["connections"]["O"] == cell["connections"]["CLKIN"] for c in design["cells"].values())
        primitive_clocks[cell_name] = {"output_hz": int(output), "calculated_vco_hz": int(output * int(p["ODIV_SEL"], 2)),
                                      "phase_parameter": p["PSDA_SEL"].strip()}
    divider = design["cells"]["clocks.video_divider"]
    serial_bits = design["netnames"]["clocks.serial_clk"]["bits"]
    pixel_bits = design["netnames"]["clocks.pixel_clk"]["bits"]
    assert divider["type"] == "CLKDIV" and divider["parameters"]["DIV_MODE"] == "5"
    assert divider["connections"]["HCLKIN"] == serial_bits and divider["connections"]["CLKOUT"] == pixel_bits
    serializers = [c for c in design["cells"].values() if c["type"] == "OSER10"]
    assert len(serializers) == 4 and all(c["connections"]["FCLK"] == serial_bits and c["connections"]["PCLK"] == pixel_bits for c in serializers)

    # Constrain internal clock nets explicitly, including after the audio input
    # buffer: this backend does not propagate that external clock target.
    # Naming related clocks here does not validate their phase relationship.
    for name, hz in [("clocks.sys_clk", 64000000), ("clocks.serial_clk", 126000000),
                     ("clocks.pixel_clk", 25200000), ("clocks.sdram_clk", 64000000),
                     ("control.audio_clk", 12288000)]:
        assert name in design["netnames"], f"Missing clock net: {name}"
        clocks.append((name, hz, "get_nets"))
    (out / "board.cst").write_text("// Generated from reviewed pin manifest; physical acceptance remains open.\n" + "\n".join(constraints) + "\n")
    (out / "board.sdc").write_text("# Clock frequency targets only; no ignored timing exceptions.\n" + "\n".join(
        f'create_clock -period {1e9/hz:.12f} [{selector} {{{name}}}]' for name, hz, selector in clocks) + "\n")
    evidence = {"scope": "all mapped top-level bits assigned to reviewed package/die pads; explicit frequency targets, not I/O timing signoff",
                "part": config["part"], "covered_top_level_bits": len(assigned),
                "differential_pairs": sum(len(p["pins"]) for p in config["ports"] if "negative_pins" in p),
                "pins": assigned, "clock_targets_hz": {name: hz for name, hz, _ in clocks},
                "clock_primitive_parameters": primitive_clocks,
                "unconstrained_top_level_bits": [], "physical_testing": False, "passed": True}
    (out / "evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
    print(f"PASS: {len(assigned)} top-level bits, no duplicate pads, {len(clocks)} explicit clock targets")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("netlist", type=Path)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("out", type=Path)
    args = parser.parse_args()
    prepare(args.netlist, args.manifest, args.out)
