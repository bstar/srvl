"""Summarize scoped board-build evidence without converting it to signoff."""

import json
from pathlib import Path
import re
import sys

mapping, checks, route, out = map(Path, sys.argv[1:5])
out.mkdir(parents=True, exist_ok=True)
mapped = json.loads((mapping / "evidence.json").read_text())
constraints = json.loads((checks / "constraints/evidence.json").read_text())
coverage = json.loads((checks / "timing-coverage/evidence.json").read_text())
normalization = json.loads((mapping / "lut-normalization.json").read_text())
exit_code = int((route / "exit-code.txt").read_text())
log = (route / "route.log").read_text()
timing = json.loads((route / "timing.json").read_text()) if (route / "timing.json").exists() else {}
applied = {name: float(mhz) for name, mhz in re.findall(r"constraining clock net '([^']+)' to ([0-9.]+) MHz", log)}
missing_targets = [name for name, hz in constraints["clock_targets_hz"].items()
                   if name not in applied or abs(applied[name] - hz / 1e6) > .01]
required_domains = {"clocks.sys_clk": 64, "clocks.pixel_clk": 25.2, "control.audio_clk": 12.288}
clock_checks = {}
for name, mhz in required_domains.items():
    row = timing.get("fmax", {}).get(name, {})
    clock_checks[name] = bool(row and abs(row["constraint"] - mhz) < .001
                              and row["achieved"] >= row["constraint"])
passed = exit_code == 0 and not missing_targets and all(clock_checks.values())
result = {
    "scope": "complete bench-board mapping, pin/clock packing and scoped route/Fmax report; incomplete timing models and no physical acceptance",
    "mapping": mapped, "constraints": constraints, "normalization": normalization,
    "timing_model_coverage": coverage,
    "route": {"artifact": str(route), "exit_code": exit_code,
              "utilization": timing.get("utilization", {}), "reported_fmax_mhz": timing.get("fmax", {}),
              "applied_clock_targets_mhz": applied, "missing_or_wrong_targets": missing_targets,
              "required_domain_checks": clock_checks, "scoped_route_checks_passed": passed},
    "complete_board_timing_signoff": False, "physical_testing": False,
}
(out / "evidence.json").write_text(json.dumps(result, indent=2) + "\n")
if passed:
    (out / "route-check-passed").touch()
print("PASS" if passed else "FAIL", "scoped route/clock checks; complete board timing signoff remains false")
print(json.dumps(result["route"], indent=2))
