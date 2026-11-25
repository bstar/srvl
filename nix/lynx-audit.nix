{
  runCommand,
  ghdl,
  yosys,
  python3,
  verilator,
  stdenv,
  gnumake,
  cc65,
  nextpnr,
  iverilog,
  quartus,
  source,
}:
let
  hdl =
    runCommand "srvl-lynx-audit-hdl"
      {
        nativeBuildInputs = [
          ghdl
          python3
        ];
      }
      ''
        python ${../scripts/prepare-lynx-audit.py} ${source} "$out" > translation.log 2>&1 || { cat translation.log; exit 1; }
        cp translation.log "$out/"
        ghdl --version > "$out/ghdl-version.txt"
      '';
  sizing =
    runCommand "srvl-lynx-audit-sizing"
      {
        nativeBuildInputs = [ yosys ];
      }
      ''
        mkdir -p "$out"
        yosys -Q -T -p 'read_verilog ${hdl}/lynx-compact.v; synth_gowin -family gw2a -top lynx_audit -noiopads -json lynx.json; stat' > "$out/synthesis.log" 2>&1 || { tail -100 "$out/synthesis.log"; exit 1; }
        cp lynx.json "$out/"
        yosys -V > "$out/yosys-version.txt"
        ln -s ${hdl} "$out/hdl"
      '';
  report =
    runCommand "srvl-lynx-audit-report"
      {
        nativeBuildInputs = [ python3 ];
      }
      ''
        mkdir "$out"
        python ${../scripts/report-lynx-audit.py} ${source} ${sizing}/lynx.json \
          ${../hardware/targets/tang-nano-20k.json} "$out/report.json"
        ln -s ${sizing} "$out/sizing"
      '';
  routeProbe =
    runCommand "srvl-lynx-audit-route-probe"
      {
        nativeBuildInputs = [
          python3
          nextpnr
        ];
      }
      ''
        mkdir "$out"
        python ${../scripts/prepare-lynx-route-probe.py} ${sizing}/lynx.json probe.json
        cp probe.scope.json "$out/scope.json"
        # Retain a failed timing/packing result as evidence, never as acceptance.
        set +e
        nextpnr-himbaechel --device GW2AR-LV18QN88C8/I7 -o family=GW2A-18C \
          -o cst=${../hardware/tests/lynx-route-probe.cst} --json probe.json \
          --freq 64 --seed 1 --threads 4 --report "$out/timing.json" \
          --write "$out/routed.json" > "$out/route.log" 2>&1
        result=$?
        set -e
        echo "$result" > "$out/exit-code.txt"
        tail -40 "$out/route.log"
        nextpnr-himbaechel --version > "$out/tool-version.txt" 2>&1
      '';
  ramCheck =
    runCommand "srvl-lynx-audit-ram-check"
      {
        nativeBuildInputs = [
          ghdl
          iverilog
        ];
      }
      ''
        ghdl -a --std=08 ${hdl}/rtl/dpram.vhd
        ghdl --synth --std=08 --out=verilog -gaddr_width=6 dpram > ram.v 2> translation.log || { cat translation.log; exit 1; }
        iverilog -g2012 -s lynx_ram_tb -o ram-check ram.v \
          ${../hardware/tests/lynx-ram-tb.sv} ${quartus.unwrapped}/quartus/eda/sim_lib/altera_mf.v > compile.log 2>&1 || { tail -40 compile.log; exit 1; }
        vvp ram-check > test.log 2>&1 || { cat test.log; exit 1; }
        cat test.log
        mkdir "$out"
        cp ram.v translation.log compile.log test.log "$out/"
      '';
  audit =
    runCommand "srvl-lynx-compatibility-audit"
      {
        nativeBuildInputs = [ python3 ];
      }
      ''
        mkdir "$out"
        python ${../scripts/summarize-lynx-audit.py} ${report} ${smoke} ${ramCheck} ${routeProbe} "$out/evidence.json"
        ln -s ${report} "$out/synthesis"
        ln -s ${smoke} "$out/diagnostic"
        ln -s ${ramCheck} "$out/ram-model-comparison"
        ln -s ${routeProbe} "$out/core-route-probe"
      '';
  diagnostic =
    runCommand "srvl-lynx-audit-diagnostic"
      {
        nativeBuildInputs = [ cc65 ];
      }
      ''
        ca65 ${../hardware/tests/lynx-audit.s} -o diagnostic.o
        printf 'MEMORY { RAM: start = $0200, size = $1000, file = %%O; }\nSEGMENTS { CODE: load = RAM, type = ro; }\n' > diagnostic.cfg
        mkdir "$out"
        ld65 -C diagnostic.cfg diagnostic.o -o "$out/diagnostic.bin"
      '';
  smoke =
    runCommand "srvl-lynx-audit-smoke"
      {
        nativeBuildInputs = [
          verilator
          stdenv.cc
          gnumake
        ];
      }
      ''
        # Warnings are fatal for the project wrapper; only the translated upstream core is waived.
        printf '`verilator_config\nlint_off -file "%s"\n' ${hdl}/lynx-compact.v > upstream.vlt
        verilator --cc --exe --build -j 4 -Wall -Wno-DECLFILENAME -Wno-PROCASSINIT -Wno-ALWNEVER --top-module lynx_audit --Mdir obj \
          -CFLAGS -O2 upstream.vlt ${hdl}/lynx-compact.v ${../sim/lynx-audit.cpp} > compile.log 2>&1 || { tail -80 compile.log; exit 1; }
        ./obj/Vlynx_audit ${diagnostic}/diagnostic.bin > test.log 2>&1 || { cat test.log; exit 1; }
        cat test.log
        mkdir "$out"
        cp compile.log test.log "$out/"
        ln -s ${hdl} "$out/hdl"
        ln -s ${diagnostic} "$out/diagnostic"
      '';
in
{
  inherit
    hdl
    sizing
    smoke
    report
    routeProbe
    ramCheck
    audit
    ;
}
