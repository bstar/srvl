{
  lib,
  runCommand,
  verilator,
  stdenv,
  gnumake,
  python3,
  yosys,
  cc65,
  cpuHdl,
}:
let
  previewPython = python3.withPackages (ps: [ ps.pillow ]);
  source = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../hardware/enhanced/cb_scaled_blitter.sv
      ../sim/scaled-blitter-model.hpp
      ../sim/scaled-blitter.cpp
    ];
  };
  memorySource = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../hardware/enhanced/cb_scaled_blitter.sv
      ../hardware/memory/cb_graphics_arbiter.sv
      ../hardware/memory/cb_graphics_sdram.sv
      ../hardware/tests/enhanced-blitter-memory-top.sv
      ../sim/scaled-blitter-model.hpp
      ../sim/scaled-blitter-memory.cpp
      ../sim/sdram-model.hpp
    ];
  };
  serviceSource = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../hardware/memory/cb_graphics_arbiter.sv
      ../hardware/memory/cb_graphics_sdram.sv
      ../hardware/tests/graphics-memory-top.sv
      ../sim/graphics-memory.cpp
      ../sim/sdram-model.hpp
    ];
  };
  nativeSource = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../hardware/enhanced
      ../hardware/memory
      ../hardware/tests/native-graphics-top.sv
      ../sim/native-graphics-model.hpp
      ../sim/scaled-blitter-model.hpp
      ../sim/sdram-model.hpp
      ../sim/blitter-mmio.cpp
      ../sim/native-graphics.cpp
      ../firmware/enhanced-diagnostic.s
      ../firmware/graphics-abi.inc
      ../scripts/make-graphics-abi.py
      ../firmware/rom.cfg
    ];
  };
  abiCheck =
    runCommand "srvl-graphics-abi-check"
      {
        nativeBuildInputs = [ python3 ];
      }
      ''
        python ${nativeSource}/scripts/make-graphics-abi.py ${nativeSource}/hardware/enhanced/graphics-abi.json generated
        cmp generated/cb_abi_pkg.sv ${nativeSource}/hardware/enhanced/cb_abi_pkg.sv
        cmp generated/graphics-abi.inc ${nativeSource}/firmware/graphics-abi.inc
        mkdir "$out"
        cp generated/* "$out/"
      '';
  mmioCheck =
    runCommand "srvl-blitter-mmio-check"
      {
        nativeBuildInputs = [
          verilator
          stdenv.cc
          gnumake
          python3
          yosys
        ];
      }
      ''
        verilator --cc --exe --build -j 4 -Wall -Wno-DECLFILENAME \
          --top-module native_graphics_top -GUSE_CPU=0 --Mdir obj -CFLAGS '-O2 -std=c++17' \
          ${nativeSource}/hardware/enhanced/*.sv ${nativeSource}/hardware/memory/*.sv ${nativeSource}/hardware/tests/native-graphics-top.sv \
          ${nativeSource}/sim/blitter-mmio.cpp > compile.log 2>&1 || { tail -100 compile.log; exit 1; }
        ./obj/Vnative_graphics_top evidence.json > test.log 2>&1 || { cat test.log; exit 1; }
        cat test.log
        yosys -Q -T -p 'read_verilog -sv ${nativeSource}/hardware/enhanced/*.sv; synth_gowin -family gw2a -top cb_blitter_mmio -noiopads -json mmio.json; stat' \
          > synthesis.log 2>&1 || { tail -100 synthesis.log; exit 1; }
        python - <<'PY'
        import collections,json
        cells=collections.Counter(c['type'] for c in json.load(open('mmio.json'))['modules']['cb_blitter_mmio']['cells'].values())
        assert not any('LATCH' in t.upper() for t in cells), 'Unintended latch'
        assert not any('MULT' in t or t in ['DPB','SDPB','DPX9B','SDPX9B'] for t in cells), 'Unexpected DSP/BRAM'
        json.dump({'scope':'dual-clock MMIO plus scaled blitter; no CPU/SDRAM or integrated route/timing',
                   'mapped_cells':dict(cells),'passed':True},open('synthesis.json','w'),indent=2)
        PY
        mkdir "$out"
        cp compile.log test.log evidence.json synthesis.log synthesis.json mmio.json "$out/"
        ln -s ${nativeSource} "$out/source"
        verilator --version > "$out/tool-version.txt"
      '';
  nativeCpuCheck =
    runCommand "srvl-native-graphics-check"
      {
        nativeBuildInputs = [
          verilator
          stdenv.cc
          gnumake
          python3
          cc65
        ];
      }
      ''
        ca65 ${nativeSource}/firmware/enhanced-diagnostic.s -l diagnostic.lst -o diagnostic.o
        ld65 -C ${nativeSource}/firmware/rom.cfg diagnostic.o -o diagnostic.bin -m diagnostic.map
        python - <<'PY'
        from pathlib import Path
        data=Path('diagnostic.bin').read_bytes()
        assert len(data)==32768
        Path('native-graphics.hex').write_text("".join(f'{b:02x}\n' for b in data))
        PY
        # Warnings are fatal for project RTL; only the pinned upstream CPU is waived.
        printf '`verilator_config\nlint_off -file "%s"\n' ${cpuHdl}/cpu.v > upstream.vlt
        verilator --cc --exe --build -j 4 -Wall -Wno-DECLFILENAME -Wno-PROCASSINIT --top-module native_graphics_top --Mdir obj \
          -CFLAGS '-O2 -std=c++17' upstream.vlt ${cpuHdl}/cpu.v ${nativeSource}/hardware/enhanced/*.sv ${nativeSource}/hardware/memory/*.sv \
          ${nativeSource}/hardware/tests/native-graphics-top.sv ${nativeSource}/sim/native-graphics.cpp \
          > compile.log 2>&1 || { tail -100 compile.log; exit 1; }
        ./obj/Vnative_graphics_top evidence.json > test.log 2>&1 || { cat test.log; exit 1; }
        cat test.log
        ${previewPython}/bin/python - <<'PY'
        from pathlib import Path
        from PIL import Image
        assert Path('native-scene-0.ppm').read_bytes()==Path('native-scene-1.ppm').read_bytes()==Path('native-scene-2.ppm').read_bytes()
        image=Image.open('native-scene-0.ppm')
        assert image.size==(320,204)
        image.save('native-scene.png')
        PY
        mkdir "$out"
        cp compile.log test.log evidence.json diagnostic.bin diagnostic.lst diagnostic.map native-graphics.hex native-scene*.ppm native-scene.png "$out/"
        ln -s ${nativeSource} "$out/source"
        ln -s ${cpuHdl} "$out/cpu-source"
        verilator --version > "$out/tool-version.txt"
      '';
  memoryServiceCheck =
    runCommand "srvl-graphics-memory-check"
      {
        nativeBuildInputs = [
          verilator
          stdenv.cc
          gnumake
          python3
          yosys
        ];
      }
      ''
        verilator --cc --exe --build -j 4 -Wall -Wno-DECLFILENAME \
          --top-module graphics_memory_top --Mdir obj -CFLAGS '-O2 -std=c++17' \
          ${serviceSource}/hardware/memory/cb_graphics_arbiter.sv \
          ${serviceSource}/hardware/memory/cb_graphics_sdram.sv \
          ${serviceSource}/hardware/tests/graphics-memory-top.sv ${serviceSource}/sim/graphics-memory.cpp \
          > compile.log 2>&1 || { tail -100 compile.log; exit 1; }
        ./obj/Vgraphics_memory_top evidence.json > test.log 2>&1 || { cat test.log; exit 1; }
        cat test.log
        for module in cb_graphics_arbiter cb_graphics_sdram; do
          yosys -Q -T -p "read_verilog -sv ${serviceSource}/hardware/memory/$module.sv; synth_gowin -family gw2a -top $module -noiopads -json $module.json; stat" \
            > "$module.log" 2>&1 || { tail -100 "$module.log"; exit 1; }
        done
        python - <<'PY'
        import collections,json
        mapping={}
        for name in ['cb_graphics_arbiter','cb_graphics_sdram']:
            cells=collections.Counter(c['type'] for c in json.load(open(name+'.json'))['modules'][name]['cells'].values())
            assert not any('LATCH' in t.upper() for t in cells), 'Unintended latch'
            assert not any('MULT' in t or t in ['DPB','SDPB','DPX9B','SDPX9B'] for t in cells), 'Unexpected DSP/BRAM'
            mapping[name]=dict(cells)
        json.dump({'scope':'separately mapped enhanced arbiter/controller; no integrated route/timing',
                   'mapped_cells':mapping,'passed':True},open('synthesis.json','w'),indent=2)
        PY
        mkdir "$out"
        cp compile.log test.log evidence.json synthesis.json cb_graphics_*.json cb_graphics_*.log "$out/"
        ln -s ${serviceSource} "$out/source"
        verilator --version > "$out/verilator-version.txt"
        yosys -V > "$out/yosys-version.txt"
      '';
  blitterCheck =
    runCommand "srvl-scaled-blitter-check"
      {
        nativeBuildInputs = [
          verilator
          stdenv.cc
          gnumake
          python3
          yosys
        ];
      }
      ''
        verilator --cc --exe --build -j 4 -Wall --top-module cb_scaled_blitter --Mdir obj \
          -CFLAGS '-O2 -std=c++17' ${source}/hardware/enhanced/cb_scaled_blitter.sv \
          ${source}/sim/scaled-blitter.cpp > compile.log 2>&1 || { tail -100 compile.log; exit 1; }
        ./obj/Vcb_scaled_blitter evidence.json > test.log 2>&1 || { cat test.log; exit 1; }
        cat test.log
        yosys -Q -T -p 'read_verilog -sv ${source}/hardware/enhanced/cb_scaled_blitter.sv; synth_gowin -family gw2a -top cb_scaled_blitter -noiopads -json blitter.json; stat' \
          > synthesis.log 2>&1 || { tail -100 synthesis.log; exit 1; }
        python - <<'PY'
        import collections,json
        cells=collections.Counter(c['type'] for c in json.load(open('blitter.json'))['modules']['cb_scaled_blitter']['cells'].values())
        assert not any('LATCH' in t.upper() for t in cells), 'Unintended latch'
        assert not any('MULT' in t or t in ['DPB','SDPB','DPX9B','SDPX9B'] for t in cells), 'Unexpected DSP/BRAM use'
        json.dump({'scope':'standalone scaled-blitter mapped cells; no integrated enhanced fit/timing',
                   'mapped_cells':dict(cells),'passed':True},open('synthesis.json','w'),indent=2)
        print('PASS: scaled blitter maps without DSP, BRAM or unintended latches')
        PY
        mkdir "$out"
        cp compile.log test.log evidence.json synthesis.log synthesis.json blitter.json "$out/"
        ln -s ${source} "$out/source"
        verilator --version > "$out/verilator-version.txt"
        yosys -V > "$out/yosys-version.txt"
      '';
  blitterMemoryCheck =
    runCommand "srvl-scaled-blitter-memory-check"
      {
        nativeBuildInputs = [
          verilator
          stdenv.cc
          gnumake
          python3
        ];
      }
      ''
        verilator --cc --exe --build -j 4 -Wall -Wno-DECLFILENAME -Wno-PROCASSINIT \
          --top-module enhanced_blitter_memory_top --Mdir obj -CFLAGS '-O2 -std=c++17' \
          ${memorySource}/hardware/enhanced/cb_scaled_blitter.sv \
          ${memorySource}/hardware/memory/cb_graphics_arbiter.sv ${memorySource}/hardware/memory/cb_graphics_sdram.sv \
          ${memorySource}/hardware/tests/enhanced-blitter-memory-top.sv ${memorySource}/sim/scaled-blitter-memory.cpp \
          > compile.log 2>&1 || { tail -100 compile.log; exit 1; }
        ./obj/Venhanced_blitter_memory_top evidence.json > test.log 2>&1 || { cat test.log; exit 1; }
        cat test.log
        ${previewPython}/bin/python - <<'PY'
        from PIL import Image
        image=Image.open('scaled-scene.ppm')
        assert image.size==(320,204)
        image.save('scaled-scene.png')
        PY
        mkdir "$out"
        cp compile.log test.log evidence.json scaled-scene.ppm scaled-scene.png "$out/"
        ln -s ${memorySource} "$out/source"
        verilator --version > "$out/tool-version.txt"
      '';
in
{
  inherit
    abiCheck
    blitterCheck
    blitterMemoryCheck
    memoryServiceCheck
    mmioCheck
    nativeCpuCheck
    ;
}
