{
  lib,
  runCommand,
  verilator,
  stdenv,
  gnumake,
  python3,
  yosys,
  nextpnr,
  cc65,
  cpuHdl,
}:
let
  previewPython = python3.withPackages (ps: [ ps.pillow ]);
  source = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../hardware/enhanced
      ../hardware/memory
      ../hardware/display
      ../hardware/boards/tang_nano20k
      ../firmware/enhanced-demo.s
      ../firmware/graphics-abi.inc
      ../firmware/rom.cfg
      ../sim/enhanced-system.cpp
      ../sim/scaled-blitter-model.hpp
      ../sim/sdram-model.hpp
      ../scripts/normalize-gowin-luts.py
      ../scripts/prepare-enhanced-board.py
    ];
  };
  # The demo ROM, and a negative ROM that draws into the displayed surface.
  roms =
    runCommand "chipbuilder-enhanced-demo-rom"
      {
        nativeBuildInputs = [
          cc65
          python3
        ];
      }
      ''
        mkdir "$out"
        ca65 ${source}/firmware/enhanced-demo.s -l "$out/enhanced-demo.lst" -o demo.o
        ca65 -D BAD_OWNER=1 ${source}/firmware/enhanced-demo.s -o bad.o
        ld65 -C ${source}/firmware/rom.cfg demo.o -o "$out/enhanced-demo.bin" -m "$out/enhanced-demo.map"
        ld65 -C ${source}/firmware/rom.cfg bad.o -o "$out/bad-owner.bin"
        python - "$out" <<'PY'
        from pathlib import Path
        import sys
        out=Path(sys.argv[1])
        for name in ['enhanced-demo','bad-owner']:
            data=(out/f'{name}.bin').read_bytes()
            assert len(data)==32768
            (out/f'{name}.hex').write_text("".join(f'{b:02x}\n' for b in data))
        assert (out/'enhanced-demo.bin').read_bytes()!=(out/'bad-owner.bin').read_bytes()
        PY
      '';
  systemCheck =
    runCommand "chipbuilder-enhanced-system-check"
      {
        nativeBuildInputs = [
          verilator
          stdenv.cc
          gnumake
          python3
        ];
      }
      ''
        # Warnings are fatal for project RTL; only the pinned upstream CPU is waived.
        printf '`verilator_config\nlint_off -file "%s"\n' ${cpuHdl}/cpu.v > upstream.vlt
        verilator --cc --exe --build -j 4 -Wall -Wno-DECLFILENAME -Wno-PROCASSINIT \
          --top-module cb_enhanced_system --prefix Venhanced_system --Mdir obj -CFLAGS '-O2 -std=c++17' \
          upstream.vlt ${cpuHdl}/cpu.v ${source}/hardware/enhanced/*.sv ${source}/hardware/memory/*.sv \
          ${source}/hardware/boards/tang_nano20k/cb_reset_sync.sv \
          ${source}/hardware/enhanced/system/cb_enhanced_system.sv ${source}/sim/enhanced-system.cpp \
          > compile.log 2>&1 || { tail -100 compile.log; exit 1; }
        cp ${roms}/enhanced-demo.hex enhanced-demo.hex
        ./obj/Venhanced_system evidence.json > test.log 2>&1 || { cat test.log; exit 1; }
        cp --remove-destination ${roms}/bad-owner.hex enhanced-demo.hex
        ./obj/Venhanced_system --bad-owner >> test.log 2>&1 || { cat test.log; exit 1; }
        cat test.log
        test "$(grep -c '^PASS' test.log)" = 2
        ${previewPython}/bin/python - <<'PY'
        from PIL import Image
        image=Image.open('enhanced-demo.ppm')
        assert image.size==(320,204)
        image.save('enhanced-demo.png')
        PY
        mkdir "$out"
        cp compile.log test.log evidence.json enhanced-demo.ppm enhanced-demo.png "$out/"
        ln -s ${source} "$out/source"
        ln -s ${roms} "$out/roms"
        ln -s ${cpuHdl} "$out/cpu-source"
        verilator --version > "$out/tool-version.txt"
      '';
  mapping =
    runCommand "chipbuilder-enhanced-board-mapping"
      {
        nativeBuildInputs = [
          yosys
          python3
        ];
      }
      ''
        cp ${roms}/enhanced-demo.hex enhanced-demo.hex
        yosys -Q -T -p 'read_verilog ${cpuHdl}/cpu.v; read_verilog -sv ${source}/hardware/enhanced/*.sv ${source}/hardware/enhanced/system/*.sv ${source}/hardware/memory/*.sv ${source}/hardware/display/*.sv ${source}/hardware/boards/tang_nano20k/*.sv; synth_gowin -family gw2a -top cb_enhanced_tang_board -json raw-board.json; stat' \
          > synthesis.log 2>&1 || { tail -100 synthesis.log; exit 1; }
        python ${source}/scripts/normalize-gowin-luts.py raw-board.json board.json lut-normalization.json cb_enhanced_tang_board
        python - <<'PY'
        import collections,json
        top=json.load(open('board.json'))['modules']['cb_enhanced_tang_board']
        cells=collections.Counter(c['type'] for c in top['cells'].values())
        brams=sum(n for t,n in cells.items() if t in ['SP','SPX9','DPB','SDPB','DPX9B','SDPX9B'])
        registers=sum(n for t,n in cells.items() if t.startswith('DFF'))
        assert 0<brams<=46, f'Unexpected RAM mapping: {dict(cells)}'
        assert registers<=15552, 'Register capacity exceeded'
        assert not any('LATCH' in t.upper() for t in cells), 'Unintended latch'
        assert not any('MULT' in t for t in cells), 'Unexpected DSP'
        for primitive,count in [('rPLL',2),('CLKDIV',2),('OSER10',4),('TLVDS_OBUF',4)]:
            assert cells[primitive]==count, f'{primitive}: expected {count}, got {cells[primitive]}'
        # Every clock pin must be driven by a clock primitive or a pad, never by logic.
        driver={}
        for cell in top['cells'].values():
            for port,bits in cell['connections'].items():
                if cell['port_directions'].get(port)=='output':
                    for bit in bits: driver[bit]=cell['type']
        clock_pins=0
        for name,cell in top['cells'].items():
            for port in ['CLK','CLKA','CLKB','PCLK','FCLK']:
                for bit in cell['connections'].get(port,[]):
                    clock_pins+=1
                    assert driver.get(bit) in ['rPLL','CLKDIV'], f'{name}.{port} is clocked by {driver.get(bit)}'
        result={'scope':'enhanced skeleton bench top: R65C02, block-RAM memory and demo ROM, MMIO blitter, video control, tile planes, native scanout, shared SDRAM service, clock/reset, serializer primitives and I/O; mapped only',
                'mapped_cells':dict(cells),'block_rams':brams,'registers':registers,
                'falling_edge_registers':sum(n for t,n in cells.items() if t.startswith('DFFN')),
                'lut1_to_lut4_cells':sum(cells[f'LUT{i}'] for i in range(1,5)),
                'alu_cells':cells['ALU'],'clock_pins_checked':clock_pins,'logic_driven_clock_pins':0,
                'place_and_route_passed':False,'board_timing_signoff':False,'physical_testing':False,
                'passed_synthesis_checks':True}
        json.dump(result,open('evidence.json','w'),indent=2)
        print('PASS: enhanced-board mapping,',brams,'block RAMs,',registers,'registers, no logic-driven clock')
        PY
        mkdir "$out"
        cp synthesis.log board.json evidence.json lut-normalization.json "$out/"
        ln -s ${source} "$out/source"
        ln -s ${cpuHdl} "$out/cpu-source"
        yosys -V > "$out/yosys-version.txt"
      '';
  constraints =
    runCommand "chipbuilder-enhanced-board-constraints" { nativeBuildInputs = [ python3 ]; }
      ''
        python ${source}/scripts/prepare-enhanced-board.py ${mapping}/board.json \
          ${source}/hardware/boards/tang_nano20k/pins.json "$out"
      '';
  route = runCommand "chipbuilder-enhanced-board-route" { nativeBuildInputs = [ nextpnr ]; } ''
    mkdir "$out"
    set +e
    nextpnr-himbaechel --device GW2AR-LV18QN88C8/I7 -o family=GW2A-18C \
      -o cst=${constraints}/board.cst --sdc ${constraints}/board.sdc --json ${mapping}/board.json \
      --freq 64 --seed 1 --threads 4 --detailed-timing-report --report "$out/timing.json" \
      --write "$out/routed.json" > "$out/route.log" 2>&1
    result=$?
    set -e
    echo "$result" > "$out/exit-code.txt"
    tail -50 "$out/route.log"
    ln -s ${mapping} "$out/mapping"
    ln -s ${constraints} "$out/constraints"
    nextpnr-himbaechel --version > "$out/tool-version.txt" 2>&1
  '';
  # Open-flow route and clock-frequency estimates only. The pinned tools have
  # no serializer or I/O timing model, and nothing here is a physical result.
  routeCheck = runCommand "chipbuilder-enhanced-board-check" { nativeBuildInputs = [ python3 ]; } ''
    test "$(cat ${route}/exit-code.txt)" = 0 || { tail -60 ${route}/route.log; exit 1; }
    mkdir "$out"
    python - ${route} ${mapping} "$out/evidence.json" <<'PY'
    import json,re,sys
    from pathlib import Path
    route,mapping,out=map(Path,sys.argv[1:4])
    log=(route/'route.log').read_text()
    assert 'violat' not in log.split('Info: Max frequency')[-1].lower(), 'timing violation after routing'
    clocks={}
    for name,mhz,verdict,target in re.findall(r"Max frequency for clock\s+'([^']+)': ([0-9.]+) MHz \((PASS|FAIL) at ([0-9.]+) MHz\)",log):
        clocks[name]={'estimated_mhz':float(mhz),'target_mhz':float(target),'passed':verdict=='PASS'}
    assert set(clocks)=={'memory_clk','clocks.sys_clk','clocks.pixel_clk'}, clocks
    assert all(c['passed'] for c in clocks.values()), clocks
    used={}
    for name,count,total in re.findall(r"Info:\s+(\w+):\s+(\d+)/\s*(\d+)",log.split('Device utilisation:')[-1]):
        if int(count): used[name]={'used':int(count),'available':int(total)}
    assert used['LUT4']['used']<used['LUT4']['available'] and used['BSRAM']['used']<=used['BSRAM']['available']
    result={'scope':'enhanced skeleton bench top placed and routed with open tools; frequency estimates for three clock nets only, no serializer/DSP/I/O timing model, no cross-domain analysis and no physical test',
            'mapping':json.loads((mapping/'evidence.json').read_text()),'placed_resources':used,'clocks':clocks,
            'seed':1,'board_timing_signoff':False,'physical_testing':False,'passed':True}
    out.write_text(json.dumps(result,indent=2)+'\n')
    print('PASS: enhanced board routes;',', '.join(f"{n} {c['estimated_mhz']} MHz (target {c['target_mhz']})" for n,c in clocks.items()))
    PY
    ln -s ${route} "$out/route"
  '';
in
{
  inherit
    constraints
    mapping
    roms
    route
    routeCheck
    systemCheck
    ;
}
