{
  lib,
  runCommand,
  verilator,
  stdenv,
  gnumake,
  python3,
  yosys,
  nextpnr,
  apycula,
  lynxHdl,
}:
let
  dviSource = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../hardware/display
      ../hardware/tests/dvi-encoder-top.sv
      ../sim/dvi-encoder.cpp
      ../sim/tmds-model.hpp
    ];
  };
  controlSource = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../hardware/boards/tang_nano20k/cb_reset_sync.sv
      ../hardware/boards/tang_nano20k/cb_board_control.sv
      ../sim/board-control.cpp
    ];
  };
  dviCheck =
    runCommand "chipbuilder-dvi-encoder-check"
      {
        nativeBuildInputs = [
          verilator
          stdenv.cc
          gnumake
          python3
        ];
      }
      ''
        verilator --cc --exe --build -j 4 -Wall -Wno-DECLFILENAME --top-module dvi_encoder_top --Mdir obj \
          -CFLAGS '-O2 -std=c++17' ${dviSource}/hardware/display/*.sv ${dviSource}/hardware/tests/dvi-encoder-top.sv \
          ${dviSource}/sim/dvi-encoder.cpp > compile.log 2>&1 || { tail -100 compile.log; exit 1; }
        ./obj/Vdvi_encoder_top evidence.json > test.log 2>&1 || { cat test.log; exit 1; }
        cat test.log
        mkdir "$out"
        cp compile.log test.log evidence.json "$out/"
        ln -s ${dviSource} "$out/source"
        verilator --version > "$out/tool-version.txt"
      '';
  controlCheck =
    runCommand "chipbuilder-board-control-check"
      {
        nativeBuildInputs = [
          verilator
          stdenv.cc
          gnumake
          python3
        ];
      }
      ''
        verilator --cc --exe --build -j 4 -Wall --top-module cb_board_control --Mdir obj \
          -CFLAGS '-O2 -std=c++17' ${controlSource}/hardware/boards/tang_nano20k/cb_reset_sync.sv \
          ${controlSource}/hardware/boards/tang_nano20k/cb_board_control.sv \
          ${controlSource}/sim/board-control.cpp > compile.log 2>&1 || { tail -100 compile.log; exit 1; }
        ./obj/Vcb_board_control evidence.json > test.log 2>&1 || { cat test.log; exit 1; }
        cat test.log
        mkdir "$out"
        cp compile.log test.log evidence.json "$out/"
        ln -s ${controlSource} "$out/source"
        verilator --version > "$out/tool-version.txt"
      '';
in
{
  inherit dviCheck controlCheck;
}
