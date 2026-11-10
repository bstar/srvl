"""Stage the pinned MiSTer framework and this project's adapter in a build dir."""
from pathlib import Path
import shutil
import stat
import sys

template, project, dest = map(lambda p: Path(p).resolve(), sys.argv[1:])
if dest.exists():
    raise SystemExit(f"Refusing to overwrite existing build directory: {dest}")
dest.mkdir(parents=True)
shutil.copytree(template / "sys", dest / "sys")
shutil.copytree(template / "rtl", dest / "rtl")
# Nix inputs are read-only, and copytree preserves those permissions. Quartus
# needs writable project directories; changing modes leaves source bytes intact.
for path in dest.rglob("*"):
    path.chmod(path.stat().st_mode | stat.S_IWUSR)
shutil.copy(template / "LICENSE", dest / "LICENSE.MiSTer")
qsf = (template / "Template.qsf").read_text().replace("Template.sdc", "Chipbuilder.sdc")
# Bound parallelism and placement seed rather than inheriting host CPU count.
qsf = qsf.replace("NUM_PARALLEL_PROCESSORS ALL", "NUM_PARALLEL_PROCESSORS 4")
(dest / "Chipbuilder.qsf").write_text(qsf)
(dest / "Chipbuilder.qpf").write_text('QUARTUS_VERSION = "17.0"\nPROJECT_REVISION = "Chipbuilder"\n')
shutil.copy(template / "Template.sdc", dest / "Chipbuilder.sdc")
shutil.copy(project / "hardware/mister/Chipbuilder.sv", dest / "Chipbuilder.sv")
shutil.copy(project / "hardware/rtl/chipbuilder_demo.sv", dest / "rtl/chipbuilder_demo.sv")
# A project-specific PLL replaces the template's 20 MHz configuration.
# Keep the sys framework byte-for-byte unchanged.
pll = dest / "rtl/pll/pll_0002.v"
text = pll.read_text()
assert text.count('20.000000 MHz') == 1, "Pinned PLL no longer matches expected template"
pll.write_text(text.replace('20.000000 MHz', '50.400000 MHz'))
# Omit generated parameter metadata that describes the original 20 MHz setup.
(dest / "rtl/pll.qip").write_text('''set_global_assignment -library pll -name VERILOG_FILE [file join $::quartus(qip_path) "pll.v"]
set_global_assignment -library pll -name VERILOG_FILE [file join $::quartus(qip_path) "pll/pll_0002.v"]
set_global_assignment -library pll -name QIP_FILE [file join $::quartus(qip_path) "pll/pll_0002.qip"]
''')
(dest / "files.qip").write_text('''set_global_assignment -name SYSTEMVERILOG_FILE rtl/chipbuilder_demo.sv
set_global_assignment -name SYSTEMVERILOG_FILE Chipbuilder.sv
set_global_assignment -name SDC_FILE Chipbuilder.sdc
''')
# Replace the wall-clock hook with a deterministic hook, leaving sys/ intact.
qsf_path = dest / "Chipbuilder.qsf"
qsf_path.write_text(qsf_path.read_text() + '\nset_global_assignment -name PRE_FLOW_SCRIPT_FILE "quartus_sh:chipbuilder_build_id.tcl"\n')
(dest / "chipbuilder_build_id.tcl").write_text('post_message "Using pinned Chipbuilder build ID"\n')
(dest / "build_id.v").write_text('`define BUILD_DATE "20261028"\n')
print(dest)
