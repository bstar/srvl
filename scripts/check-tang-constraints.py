"""Fault-injection checks for the actual mapped Tang board constraint input."""

import copy
import importlib.util
import json
from pathlib import Path
import sys
import tempfile

spec = importlib.util.spec_from_file_location("prepare_board", Path(__file__).with_name("prepare-tang-board.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
netlist, manifest = map(Path, sys.argv[1:3])
original = json.loads(manifest.read_text())
for group in original["ports"]:
    if "negative_port" in group:
        assert group["primitive"] == "TLVDS_OBUF" and group["io_type"] == "LVDS25"
        assert group["drive"] == "3.5", "Review the true-LVDS board output standard"

with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    module.prepare(netlist, manifest, root / "good")
    cst = (root / "good/board.cst").read_text()
    # The pinned parser cannot infer a negative vector name from pair shorthand.
    for i, pad in enumerate([36, 38, 40]):
        assert f'IO_LOC "tmds_data_n[{i}]" {pad};' in cst
    cases = []
    config = copy.deepcopy(original)
    config["ports"] = [p for p in config["ports"] if p["port"] != "led_n"]
    cases.append(("missing port", config))
    for name, field, value, label in [
        ("audio_sd", "pins", ["69"], "duplicate pad"),
        ("sdram_dq", "pins", ["IOL3A"], "wrong bus width"),
        ("uart_rx", "direction", "output", "wrong direction"),
        ("tmds_data_p", "negative_pins", ["36"], "incomplete differential bus"),
        ("audio_ref", "reference_hz", 12000000, "wrong reference clock"),
    ]:
        config = copy.deepcopy(original)
        next(p for p in config["ports"] if p["port"] == name)[field] = value
        cases.append((label, config))
    rejected = 0
    for label, config in cases:
        faulty = root / "fault.json"
        faulty.write_text(json.dumps(config))
        try:
            module.prepare(netlist, faulty, root / "bad")
        except (AssertionError, KeyError):
            rejected += 1
        else:
            raise AssertionError(f"Invalid constraints accepted: {label}")
    design = json.loads(netlist.read_text())
    design["modules"]["lynx_tang_board"]["cells"]["clocks.video_pll"]["parameters"]["FBDIV_SEL"] = "00000000"
    faulty = root / "wrong-pll.json"
    faulty.write_text(json.dumps(design))
    try:
        module.prepare(faulty, manifest, root / "bad-pll")
    except AssertionError:
        rejected += 1
    else:
        raise AssertionError("Incorrect PLL ratio accepted")
    print(f"PASS: explicit differential vector pads and {rejected} rejected pin/clock faults on the real mapped design")
