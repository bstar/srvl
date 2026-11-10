"""Validate the development contract and optionally size a mapped CPU netlist.

This checks allocations and traffic estimates, not FPGA timing or design fit.
"""
import argparse
from collections import Counter
import json
from pathlib import Path


def require(condition, message):
    if not condition:
        raise SystemExit(message)


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("target", type=Path)
parser.add_argument("--cpu-netlist", type=Path)
parser.add_argument("--report", type=Path)
args = parser.parse_args()
target = json.loads(args.target.read_text())
fpga = target["fpga"]
report = {"target": target["name"], "scope": "allocation/traffic estimate; no physical acceptance"}

for resource in ("lut4", "ebr_blocks", "multipliers"):
    allocated = sum(item[resource] for item in target["allocations"].values())
    require(allocated <= fpga[f"{resource}_limit"] <= fpga[f"{resource}_capacity"],
            f"{resource} allocation exceeds the device/development limit")
    report[resource] = {"allocated": allocated, "limit": fpga[f"{resource}_limit"],
                        "capacity": fpga[f"{resource}_capacity"]}

io_count = sum(target["io_allocations"].values())
require(io_count <= fpga["user_io_limit"] <= fpga["user_io_capacity"], "I/O budget exceeded")
report["io"] = {"budgeted": io_count, "limit": fpga["user_io_limit"],
                "capacity": fpga["user_io_capacity"], "scope": "signal count, not ball/bank assignment"}

video = target["video"]
graphics = target["graphics"]
clocks = target["clocks_hz"]
require(clocks["pixel"] == video["total_width"] * video["total_height"] * video["fps"],
        "raster does not match the required frame rate")
require(clocks["memory"] == clocks["pixel"] * 16 == clocks["graphics"] * 2,
        "clock-family ratios changed")
require(clocks["memory"] == clocks["cpu_enhanced_target"] * 5,
        "enhanced CPU clock ratio changed")
require(graphics["local_bytes"] == 1 << graphics["address_bits"], "graphics address-space mismatch")
pixels = video["width"] * video["height"]
surfaces = pixels * graphics["surface_bytes_per_pixel"] * graphics["surface_count"]
fixed_storage = (surfaces + graphics["object_descriptors"] * graphics["descriptor_bytes"]
                 + graphics["max_tile_map_bytes"]
                 + graphics["palette_entries"] * graphics["palette_entry_bytes"])
require(fixed_storage <= graphics["local_bytes"] <= target["external_memory"]["physical_bytes"],
        "graphics storage budget exceeded")
report["graphics_fixed_bytes"] = fixed_storage
report["graphics_bytes_remaining_for_assets_and_meshes"] = graphics["local_bytes"] - fixed_storage

memory = target["external_memory"]
peak = clocks["memory"] * memory["bus_bits"] // 8
useful = memory["useful_bytes_per_second_target"]
require(0 < useful < peak, "useful memory bandwidth must leave physical overhead")
report["memory"] = {"peak_bytes_per_second": peak, "useful_target_bytes_per_second": useful}
reserve = sum(target["traffic_reserve_bytes_per_second"].values())
report["profiles"] = []
for profile in target["acceptance_profiles"]:
    require(0 <= profile["planes"] <= graphics["tile_planes"], "profile exceeds plane capacity")
    require(0 <= profile["objects"] <= graphics["object_descriptors"], "profile exceeds object table")
    require(profile["object_width"] > 0 and profile["object_height"] > 0,
            "profile object dimensions must be positive")
    require(profile["object_width"] % 2 == 0, "packed-source estimate requires an even row width")
    samples = profile["objects"] * profile["object_width"] * profile["object_height"]
    # 41 tiles cover a horizontally scrolled 320px line; map=2B, packed row=4B.
    layers = profile["planes"] * 41 * (2 + 4) * video["height"] * video["fps"]
    # Source is contiguous 4bpp at 1:1 scale; output carries 16bpp metadata.
    objects = (samples * (1 + 2 * graphics["surface_bytes_per_pixel"]) * video["fps"]) // 2
    clear_and_scan = pixels * graphics["surface_bytes_per_pixel"] * 2 * video["fps"]
    traffic = layers + objects + clear_and_scan
    require(traffic + reserve <= useful, f"{profile['name']} exceeds useful bandwidth target")
    report["profiles"].append({"name": profile["name"], "graphics_bytes_per_second": traffic,
                               "with_reserve_bytes_per_second": traffic + reserve})

if args.cpu_netlist:
    netlist = json.loads(args.cpu_netlist.read_text())
    counts = Counter(cell["type"] for cell in netlist["modules"]["core"]["cells"].values())
    require(counts["LUT4"] > 0, "CPU netlist is not mapped to ECP5 LUTs")
    # Each CCU2C occupies two LUT sites; wide-mux/FF packing is checked by P&R later.
    lut_sites = counts["LUT4"] + 2 * counts["CCU2C"]
    require(lut_sites <= target["allocations"]["cpu"]["lut4"], "CPU exceeds its logic allocation")
    report["cpu_synthesis"] = {"primitives": dict(sorted(counts.items())),
                                "estimated_lut_sites": lut_sites,
                                "scope": "CPU only; no place/route or clock acceptance"}

result = json.dumps(report, indent=2) + "\n"
if args.report:
    args.report.write_text(result)
print(result, end="")
