#!/usr/bin/env bash
# Run in `nix develop .#quartus`. No hardware is accessed.
set -euo pipefail
version=$(quartus_sh --version)
printf '%s\n' "$version"
grep -qE 'Version 17\.0\.2 Build 602' <<< "$version"
task_dir=$(mktemp -d)
trap 'rm -rf "$task_dir"' EXIT
cd "$task_dir"
cat > smoke.v <<'VERILOG'
module smoke(input wire clk, input wire a, output reg q);
  always @(posedge clk) q <= a;
endmodule
VERILOG
cat > smoke.qpf <<'PROJECT'
PROJECT_REVISION = "smoke"
PROJECT
cat > smoke.qsf <<'SETTINGS'
set_global_assignment -name FAMILY "Cyclone V"
set_global_assignment -name DEVICE 5CSEBA6U23I7
set_global_assignment -name NUM_PARALLEL_PROCESSORS 4
set_global_assignment -name TOP_LEVEL_ENTITY smoke
set_global_assignment -name VERILOG_FILE smoke.v
set_global_assignment -name SDC_FILE smoke.sdc
set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files
SETTINGS
cat > smoke.sdc <<'TIMING'
create_clock -name clk -period 20.000 [get_ports clk]
derive_clock_uncertainty
set_input_delay -clock clk 2.0 [get_ports a]
set_output_delay -clock clk 2.0 [get_ports q]
TIMING
quartus_sh --flow compile smoke
test -s output_files/smoke.sof
echo "Quartus 17.0.2.602 Cyclone V compile passed. No device was programmed."
