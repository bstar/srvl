{
  lib,
  runCommand,
  python3,
  yosys,
  nextpnr,
  apycula,
  lynxHdl,
}:
let
  buildSource = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../flake.nix
      ../flake.lock
      ../README.md
      ../nix
      ../hardware
      ../scripts
      ../sim
      ../firmware
      ../tools
      ../patches
      ../checks
    ];
  };
  source = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      (lib.fileset.fileFilter (file: file.hasExt "sv") ../hardware/boards/tang_nano20k)
      ../hardware/display
      ../hardware/tang
      ../hardware/memory
      ../hardware/video
      ../hardware/audio
    ];
  };
  mapping =
    runCommand "srvl-tang-board-mapping"
      {
        nativeBuildInputs = [
          yosys
          python3
        ];
      }
      ''
        yosys -Q -T -p 'read_verilog ${lynxHdl}/lynx-compact.v; read_verilog -sv ${source}/hardware/tang/*.sv ${source}/hardware/memory/*.sv ${source}/hardware/video/*.sv ${source}/hardware/audio/*.sv ${source}/hardware/display/*.sv ${source}/hardware/boards/tang_nano20k/*.sv; synth_gowin -family gw2a -top lynx_tang_board -json board.json; stat' \
          > synthesis.log 2>&1 || { tail -100 synthesis.log; exit 1; }
        mv board.json raw-board.json
        python ${../scripts/normalize-gowin-luts.py} raw-board.json board.json lut-normalization.json
        python - <<'PY'
        import collections,json
        top=json.load(open('board.json'))['modules']['lynx_tang_board']
        cells=collections.Counter(c['type'] for c in top['cells'].values())
        brams=sum(cells[t] for t in ['DPB','SDPB','DPX9B','SDPX9B'])
        registers=sum(n for t,n in cells.items() if t.startswith('DFF'))
        assert brams==35, f'Unexpected complete-board RAM mapping: {dict(cells)}'
        assert 6200<=registers<=15552, 'Unexpected register count or register capacity exceeded'
        assert not any('LATCH' in t.upper() for t in cells), 'Unintended latch'
        for primitive,count in [('rPLL',2),('CLKDIV',1),('OSER10',4),('TLVDS_OBUF',4)]:
            assert cells[primitive]==count, f'{primitive}: expected {count}, got {cells[primitive]}'
        result={'scope':'complete bench-board top with original console, services, RGB/audio, clock/reset, serializer primitives and I/O; mapped only',
                'mapped_cells':dict(cells),'block_rams':brams,'registers':registers,
                'lut1_to_lut4_cells':sum(cells[f'LUT{i}'] for i in range(1,5)),
                'alu_cells':cells['ALU'],'top_level_bits':sum(len(p['bits']) for p in top['ports'].values()),
                'place_and_route_passed':False,'board_timing_signoff':False,'physical_testing':False,
                'passed_synthesis_checks':True}
        json.dump(result,open('evidence.json','w'),indent=2)
        print('PASS: complete-board mapping,',brams,'block RAMs,',registers,'registers; route/timing unqualified')
        PY
        mkdir "$out"
        cp synthesis.log board.json raw-board.json evidence.json lut-normalization.json "$out/"
        ln -s ${source} "$out/source"
        ln -s ${lynxHdl} "$out/console-hdl"
        yosys -V > "$out/yosys-version.txt"
      '';
  constraints = runCommand "srvl-tang-board-constraints" { nativeBuildInputs = [ python3 ]; } ''
    python ${../scripts/prepare-tang-board.py} ${mapping}/board.json \
      ${../hardware/boards/tang_nano20k/pins.json} "$out"
    cp ${../hardware/boards/tang_nano20k/pins.json} "$out/pins.json"
  '';
  packProbe = runCommand "srvl-tang-board-pack-probe" { nativeBuildInputs = [ nextpnr ]; } ''
    mkdir "$out"
    set +e
    nextpnr-himbaechel --device GW2AR-LV18QN88C8/I7 -o family=GW2A-18C \
      -o cst=${constraints}/board.cst --sdc ${constraints}/board.sdc --json ${mapping}/board.json \
      --pack-only --write "$out/packed.json" > "$out/pack.log" 2>&1
    result=$?
    set -e
    echo "$result" > "$out/exit-code.txt"
    tail -45 "$out/pack.log"
    nextpnr-himbaechel --version > "$out/tool-version.txt" 2>&1
  '';
  route = runCommand "srvl-tang-board-route" { nativeBuildInputs = [ nextpnr ]; } ''
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
  coverage = runCommand "srvl-tang-timing-coverage" { nativeBuildInputs = [ python3 ]; } ''
    mkdir "$out"
    python ${../scripts/report-gowin-timing-coverage.py} \
      ${nextpnr}/share/nextpnr/himbaechel/gowin/chipdb-GW2A-18C.bin \
      ${nextpnr.src} ${mapping}/board.json "$out/evidence.json" > "$out/review.log"
    cat "$out/review.log"
  '';
  buildCheck = runCommand "srvl-tang-board-constraint-check" { nativeBuildInputs = [ python3 ]; } ''
    test "$(cat ${packProbe}/exit-code.txt)" = 0
    cp ${../scripts/prepare-tang-board.py} prepare-tang-board.py
    cp ${../scripts/check-tang-constraints.py} check-tang-constraints.py
    python check-tang-constraints.py ${mapping}/board.json \
      ${../hardware/boards/tang_nano20k/pins.json} > test.log 2>&1 || { cat test.log; exit 1; }
    cat test.log
    mkdir "$out"
    cp test.log "$out/"
    ln -s ${constraints} "$out/constraints"
    ln -s ${packProbe} "$out/pack-probe"
    ln -s ${coverage} "$out/timing-coverage"
  '';
  report = runCommand "srvl-tang-board-report" { nativeBuildInputs = [ python3 ]; } ''
    python ${../scripts/report-tang-board-build.py} ${mapping} ${buildCheck} ${route} "$out"
  '';
  image =
    runCommand "srvl-tang-bench-bitstream"
      {
        nativeBuildInputs = [
          apycula
          python3
        ];
      }
      ''
        test -f ${buildCheck}/test.log
        test -f ${report}/route-check-passed || {
          echo 'Scoped route/clock checks failed; inspect the retained tang-board-report artifact.' >&2
          exit 1
        }
        test "$(cat ${route}/exit-code.txt)" = 0 || {
          echo 'Board route/timing failed; inspect the retained tang-board-route artifact.' >&2
          exit 1
        }
        mkdir "$out"
        gowin_pack -d GW2A-18C -o "$out/lynx-tang-bench.fs" ${route}/routed.json \
          > "$out/pack.log" 2>&1 || { tail -80 "$out/pack.log"; exit 1; }
        test -s "$out/lynx-tang-bench.fs"
        ln -s ${route} "$out/route"
        ln -s ${mapping}/source "$out/project-rtl"
        ln -s ${buildSource} "$out/project-build-source"
        ln -s ${buildCheck} "$out/build-checks"
        ln -s ${report} "$out/build-report"
        ln -s ${lynxHdl} "$out/console-source-and-notices"
        cat > "$out/README.txt" <<'EOF'
        Untested Tang Nano 20K bench bitstream. No device is programmed by this build.
        Requires externally configured 64 / 25.2 / 12.288 MHz references.
        Host serial loading is required; no commercial BIOS/game images are included.
        Successful open-flow route/pack is not complete I/O or physical acceptance.
        Inspect the route, constraints, source and evidence before physical testing.
        EOF
        (cd "$out"
         sha256sum lynx-tang-bench.fs > sha256.txt)
        gowin_pack --help > "$out/packer-help.txt"
      '';
in
{
  inherit
    mapping
    constraints
    packProbe
    route
    buildCheck
    image
    coverage
    report
    ;
}
