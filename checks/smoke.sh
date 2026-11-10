#!/usr/bin/env bash
set -euo pipefail
iverilog -g2012 -s smoke_tb -o smoke-iverilog smoke.v smoke_tb.sv
vvp smoke-iverilog
verilator --binary --timing --top-module smoke_tb \
  --Mdir obj_dir smoke.v smoke_tb.sv > verilator.log 2>&1
./obj_dir/Vsmoke_tb
ghdl -a --std=08 smoke.vhd
ghdl -e --std=08 smoke_vhdl
ghdl -r --std=08 smoke_vhdl --assert-level=error
yosys -Q -T -p 'read_verilog smoke.v; synth -top smoke; check -assert; write_json smoke.json' > yosys.log
cc65 --cpu 65c02 -t none -o smoke.s smoke.c
ca65 --cpu 65c02 -t none -o smoke.o smoke.s
test -s smoke.json
test -s smoke.o
python3 -c 'print("HDL simulation, synthesis, and 65C02 compilation passed")'
