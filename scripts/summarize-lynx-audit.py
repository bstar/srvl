"""Require all audit stages to pass and state exactly what they establish."""
from pathlib import Path
import json
import hashlib
import sys

report_dir, smoke, ram, route, output = map(Path, sys.argv[1:])
report = json.loads((report_dir / "report.json").read_text())
scope = json.loads((route / "scope.json").read_text())
assert (route / "exit-code.txt").read_text().strip() == "0", "Core route probe failed"
timing = json.loads((route / "timing.json").read_text())
clock = timing["fmax"]["clk"]
assert clock["constraint"] == 64 and clock["achieved"] >= 64, "64 MHz target failed"
assert "PASS: translated Lynx CPU/RAM" in (smoke / "test.log").read_text()
assert (smoke / "test.log").read_text().count("all 16320 pixels") == 4, "Cold/input/warm-reset diagnostic phases missing"
assert "23931 defined port observations" in (ram / "test.log").read_text()
board = report["target"]
resources = {}
for name, capacity in [("LUT4", board["lut4_capacity"]),
                       ("DFF", board["flip_flop_capacity"]),
                       ("BSRAM", board["bsram_blocks"])]:
    measured = timing["utilization"][name]
    assert measured["available"] == capacity and measured["used"] <= capacity
    resources[name] = {**measured, "remaining": capacity - measured["used"]}
summary = {
    "upstream_revision": report["upstream_revision"],
    "part": board["part"],
    "verdict": "baseline console passes resource and registered-core timing audit; complete board integration is outside this probe",
    "source_adaptations_sha256": hashlib.sha256((report_dir / "sizing/hdl/audit-adaptations.patch").read_bytes()).hexdigest(),
    "post_route_with_test_harness": resources,
    "clock_mhz": clock,
    "test_harness": scope,
    "passed": ["translated upstream diagnostic", "warm reset/reload diagnostic", "Intel RAM model comparison",
               "Gowin block RAM mapping", "core-only placement and routing at 64 MHz"],
    "commercial_games_tested": 0,
    "playable_tang_image": False,
    "board_timing_signoff": False,
    "physical_testing": False,
    "enhanced_graphics_fit_verified": False,
    "remaining_integration": scope["omitted"],
}
output.write_text(json.dumps(summary, indent=2) + "\n")
print(summary["verdict"])
print(json.dumps(resources, indent=2))
print(f"Core clock target 64 MHz; estimated post-route maximum {clock['achieved']:.3f} MHz")
