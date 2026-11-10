{
  lib,
  runCommand,
  ghdl,
  verilator,
  stdenv,
  python3,
  gnumake,
  patch,
  cc65,
  pkg-config,
  SDL2,
  cpuSource,
  testSource,
}:
let
  cpu-hdl =
    runCommand "chipbuilder-r65c02-hdl"
      {
        nativeBuildInputs = [
          ghdl
          python3
          patch
        ];
      }
      ''
        python ${../scripts/generate-cpu.py} ${cpuSource} ${../patches/r65c02-corrections.patch} "$out" > build.log 2>&1 || { cat build.log; exit 1; }
        cp build.log "$out/"
      '';
  cpu-check =
    runCommand "chipbuilder-cpu-check"
      {
        nativeBuildInputs = [
          verilator
          stdenv.cc
          gnumake
          python3
        ];
      }
      ''
        verilator --cc --exe --build -j 4 --top-module core --Mdir obj \
          -CFLAGS -O3 ${cpu-hdl}/cpu.v ${../sim/cpu-check.cpp} > compile.log 2>&1 || { cat compile.log; exit 1; }
        mkdir -p "$out/bin" "$out/share/chipbuilder"
        cp obj/Vcore "$out/bin/chipbuilder-cpu-check"
        cp compile.log "$out/share/chipbuilder/"
        cp ${cpu-hdl}/LICENSE.txt "$out/share/chipbuilder/LICENSE.cpu.txt"
      '';
  cpu-directed = runCommand "chipbuilder-cpu-directed" { } ''
    ${cpu-check}/bin/chipbuilder-cpu-check > test.log 2>&1 || { cat test.log; exit 1; }
    cat test.log
    mkdir "$out"
    cp test.log "$out/"
  '';
  cpu-functional = runCommand "chipbuilder-cpu-functional" { } ''
    ${cpu-check}/bin/chipbuilder-cpu-check --functional ${testSource}/bin_files/6502_functional_test.bin 3469 > 6502.log 2>&1 || { cat 6502.log; exit 1; }
    cat 6502.log
    ${cpu-check}/bin/chipbuilder-cpu-check --functional ${testSource}/bin_files/65C02_extended_opcodes_test.bin 24f1 > 65c02.log 2>&1 || { cat 65c02.log; exit 1; }
    cat 65c02.log
    mkdir "$out"
    cp *.log ${testSource}/license.txt "$out/"
    cp ${cpu-directed}/test.log "$out/directed.log"
  '';
  graphics-data =
    runCommand "chipbuilder-graphics-rom"
      {
        nativeBuildInputs = [ python3 ];
      }
      ''
        python ${../scripts/make-assets.py} "$out"
      '';
  game-data =
    runCommand "chipbuilder-courier-rom"
      {
        nativeBuildInputs = [
          cc65
          python3
        ];
      }
      ''
        python ${../scripts/make-mazes.py} maze-data.inc
        cmp maze-data.inc ${../firmware/maze-data.inc}
        python ${../scripts/build-rom.py} ${../firmware} "$out"
        ln -s ${graphics-data}/font.hex "$out/font.hex"
        ln -s ${graphics-data}/sprites.hex "$out/sprites.hex"
        cd "$out"
        sha256sum courier.bin font.hex sprites.hex > sha256.txt
      '';
  project = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../hardware/rtl/chipbuilder_cpu.sv
      ../hardware/rtl/chipbuilder_peripherals.sv
      ../hardware/rtl/chipbuilder_soc.sv
      ../sim/main.cpp
      ../sim/machine.hpp
    ];
  };
  simulatorBuild =
    hierarchical:
    runCommand "chipbuilder-simulator${lib.optionalString (!hierarchical) "-flat"}"
      {
        inherit project;
        nativeBuildInputs = [
          verilator
          stdenv.cc
          gnumake
          pkg-config
          SDL2
          python3
        ];
      }
      ''
        verilator --cc --exe --build -j 4 ${lib.optionalString hierarchical "--hierarchical"} \
          --top-module chipbuilder_soc --Mdir obj \
          "-GROM_FILE=\"${game-data}/courier.hex\"" \
        "-GFONT_FILE=\"${graphics-data}/font.hex\"" \
        "-GSPRITE_FILE=\"${graphics-data}/sprites.hex\"" \
          -CFLAGS "-O3 $(pkg-config --cflags sdl2)" -LDFLAGS "$(pkg-config --libs sdl2)" \
          ${cpu-hdl}/cpu.v "$project/hardware/rtl/chipbuilder_cpu.sv" \
          "$project/hardware/rtl/chipbuilder_peripherals.sv" "$project/hardware/rtl/chipbuilder_soc.sv" \
          "$project/sim/main.cpp" > compile.log 2>&1 || { cat compile.log; exit 1; }
        mkdir -p "$out/bin" "$out/share/chipbuilder"
        cp obj/Vchipbuilder_soc "$out/bin/chipbuilder-sim"
        cp compile.log "$out/share/chipbuilder/"
        ln -s ${game-data} "$out/share/chipbuilder/rom"
        ln -s ${cpu-hdl} "$out/share/chipbuilder/cpu-source"
      '';
  simulator = simulatorBuild true;
  simulator-flat = simulatorBuild false;
  gameTest =
    app: label:
    runCommand "chipbuilder-game-test${label}"
      {
        nativeBuildInputs = [ python3 ];
      }
      ''
        export SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy
        ${app}/bin/chipbuilder-sim --self-test --output-dir artifacts > test.log 2>&1 || { cat test.log; exit 1; }
        cat test.log
        mkdir -p "$out"
        cp test.log artifacts/* "$out/"
        for file in "$out"/*.ppm; do
          python ${../scripts/preview-to-png.py} "$file" "''${file%.ppm}.png"
        done
      '';
  game-check = gameTest simulator "";
  game-flat-check = gameTest simulator-flat "-flat";
  simulator-equivalence = runCommand "chipbuilder-simulator-equivalence" { } ''
    for artifact in title.ppm gameplay.ppm delivered.ppm link-lost.ppm jammed.ppm level-2.ppm level-3.ppm level-4.ppm campaign-complete.ppm gameplay.wav; do
      cmp "${game-check}/$artifact" "${game-flat-check}/$artifact"
    done
    mkdir "$out"
    echo 'PASS: flat and hierarchical HDL simulation produce identical game screenshots and stereo audio' > "$out/test.log"
    cat "$out/test.log"
  '';
  peripheral-check =
    runCommand "chipbuilder-peripheral-check"
      {
        nativeBuildInputs = [
          verilator
          stdenv.cc
          gnumake
          python3
        ];
      }
      ''
        verilator --cc --exe --build -j 4 --top-module chipbuilder_peripherals --Mdir obj \
          "-GFONT_FILE=\"${graphics-data}/font.hex\"" "-GSPRITE_FILE=\"${graphics-data}/sprites.hex\"" \
          -CFLAGS -O3 ${../hardware/rtl/chipbuilder_peripherals.sv} \
          ${../sim/peripheral-check.cpp} > compile.log 2>&1 || { cat compile.log; exit 1; }
        ./obj/Vchipbuilder_peripherals > test.log 2>&1 || { cat test.log; exit 1; }
        cat test.log
        mkdir "$out"
        cp compile.log test.log "$out/"
      '';
in
{
  inherit
    cpu-hdl
    cpu-check
    cpu-directed
    cpu-functional
    game-data
    simulator
    simulator-flat
    game-check
    simulator-equivalence
    peripheral-check
    ;
}
