{
  lib,
  runCommand,
  verilator,
  stdenv,
  gnumake,
  python3,
  writeShellApplication,
  cc65,
  lynxHdl,
  yosys,
}:
let
  previewPython = python3.withPackages (ps: [ ps.pillow ]);
  makeSource =
    paths:
    lib.fileset.toSource {
      root = ../.;
      fileset = lib.fileset.unions paths;
    };
  source = makeSource [
    ../hardware/tang
    ../hardware/video
    ../hardware/audio
    ../sim/sdram-model.hpp
    ../sim/lynx-tang.cpp
    ../sim/lynx-audio-monitor.hpp
    ../sim/audio-model.hpp
    ../sim/i2s-decoder.hpp
    ../hardware/tests/lynx-audit.s
  ];
  servicesSource = makeSource [
    ../hardware/tang
    ../hardware/tests/tang-services-top.sv
    ../sim/sdram-model.hpp
    ../sim/tang-services.cpp
  ];
  videoSource = makeSource [
    ../hardware/video
    ../hardware/tang/cb_memory_arbiter.sv
    ../hardware/tang/lynx_sdram.sv
    ../hardware/tests/tang-video-top.sv
    ../sim/sdram-model.hpp
    ../sim/video-pipeline.cpp
  ];
  rtlSource = makeSource [
    ../hardware/tang
    ../hardware/video
    ../hardware/audio
  ];
  audioSource = makeSource [
    ../hardware/audio
    ../sim/audio-output.cpp
    ../sim/audio-model.hpp
    ../sim/i2s-decoder.hpp
  ];
  audioCheck =
    runCommand "chipbuilder-audio-output-check"
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
        verilator --cc --exe --build -j 4 -Wall --top-module lynx_audio_output --Mdir obj \
          -CFLAGS '-O2 -std=c++17' ${audioSource}/hardware/audio/*.sv ${audioSource}/sim/audio-output.cpp \
          > compile.log 2>&1 || { tail -100 compile.log; exit 1; }
        ./obj/Vlynx_audio_output evidence.json > test.log 2>&1 || { cat test.log; exit 1; }
        cat test.log
        yosys -Q -T -p 'read_verilog -sv ${audioSource}/hardware/audio/*.sv; synth_gowin -family gw2a -top lynx_audio_output -noiopads -json audio.json; stat' \
          > synthesis.log 2>&1 || { tail -100 synthesis.log; exit 1; }
        python - <<'PY'
        import collections,json
        cells=collections.Counter(c['type'] for c in json.load(open('audio.json'))['modules']['lynx_audio_output']['cells'].values())
        assert not any('LATCH' in t.upper() for t in cells), 'Unintended latch'
        assert not any('MULT' in t or t in ['DPB','SDPB','DPX9B','SDPX9B'] for t in cells), 'Shift/add audio path unexpectedly consumes multipliers or block RAM'
        json.dump({'scope':'audio component mapped primitives; no complete board fit/timing',
                   'mapped_cells':dict(cells),'passed':True},open('synthesis.json','w'),indent=2)
        print('PASS: audio mapped without multipliers, block RAM or unintended latches')
        PY
        mkdir "$out"
        cp compile.log test.log evidence.json synthesis.log synthesis.json audio.json "$out/"
        ln -s ${audioSource} "$out/source"
        verilator --version > "$out/verilator-version.txt"
        yosys -V > "$out/yosys-version.txt"
      '';
  servicesCheck =
    runCommand "chipbuilder-tang-services-check"
      {
        nativeBuildInputs = [
          verilator
          stdenv.cc
          gnumake
          python3
        ];
      }
      ''
        # FPGA declaration initialization is intentional; test fixture names follow
        # the repository's hyphenated filenames. All other warnings are fatal.
        verilator --cc --exe --build -j 4 -Wall -Wno-PROCASSINIT -Wno-DECLFILENAME --top-module tang_services_top --Mdir obj \
          -CFLAGS '-O2 -std=c++17' ${servicesSource}/hardware/tang/*.sv \
          ${servicesSource}/hardware/tests/tang-services-top.sv ${servicesSource}/sim/tang-services.cpp \
          > compile.log 2>&1 || { tail -100 compile.log; exit 1; }
        ./obj/Vtang_services_top evidence.json > test.log 2>&1 || { cat test.log; exit 1; }
        cat test.log
        mkdir "$out"
        cp compile.log test.log evidence.json wire-fixtures.tsv "$out/"
        ln -s ${servicesSource} "$out/source"
        verilator --version > "$out/tool-version.txt"
      '';
  hostCheck = runCommand "chipbuilder-lynx-link-check" { nativeBuildInputs = [ python3 ]; } ''
    cp ${../tools/test_lynx_link.py} test_lynx_link.py
    cp ${../tools/lynx_link.py} lynx_link.py
    python test_lynx_link.py ${servicesCheck}/wire-fixtures.tsv > test.log 2>&1 || { cat test.log; exit 1; }
    cat test.log
    mkdir "$out"
    cp test.log "$out/"
    ln -s ${servicesCheck} "$out/rtl-evidence"
  '';
  host = writeShellApplication {
    name = "chipbuilder-lynx-link";
    runtimeInputs = [ (python3.withPackages (ps: [ ps.pyserial ])) ];
    text = ''
      exec python ${../tools/lynx_link.py} "$@"
    '';
  };
  coreIntegration =
    video: audio:
    runCommand
      "chipbuilder-lynx-tang-${
        if audio then
          "av"
        else if video then
          "video"
        else
          "core"
      }-check"
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
        ca65 -D TANG_CHECK_CART=1 ${lib.optionalString video "-D TANG_CHECK_VIDEO=1"} ${lib.optionalString audio "-D TANG_CHECK_AUDIO=1"} ${source}/hardware/tests/lynx-audit.s -o diagnostic.o
        printf 'MEMORY { RAM: start = $0200, size = $1000, file = %%O; }\nSEGMENTS { CODE: load = RAM, type = ro; }\n' > diagnostic.cfg
        ld65 -C diagnostic.cfg diagnostic.o -o diagnostic.bin
        # Warnings are fatal for project RTL; only the translated upstream core is waived.
        printf '`verilator_config\nlint_off -file "%s"\n' ${lynxHdl}/lynx-compact.v > upstream.vlt
        verilator --cc --exe --build -j 4 -Wall -Wno-DECLFILENAME -Wno-PROCASSINIT -Wno-ALWNEVER ${lib.optionalString video "-GVIDEO=1"} ${lib.optionalString audio "-GAUDIO=1"} --top-module lynx_tang_system --Mdir obj \
          -CFLAGS '-O2 -std=c++17 ${lib.optionalString video "-DVIDEO_CHECK"} ${lib.optionalString audio "-DAUDIO_CHECK"}' upstream.vlt ${lynxHdl}/lynx-compact.v ${source}/hardware/tang/*.sv ${source}/hardware/video/*.sv ${source}/hardware/audio/*.sv \
          ${source}/sim/lynx-tang.cpp > compile.log 2>&1 || { tail -100 compile.log; exit 1; }
        ./obj/Vlynx_tang_system diagnostic.bin evidence.json > test.log 2>&1 || { cat test.log; exit 1; }
        cat test.log
        ${lib.optionalString video ''
          ${previewPython}/bin/python - <<'PY'
          from PIL import Image
          for name in ['video-green','video-red']:
              image=Image.open(name+'.ppm')
              assert image.size==(640,480)
              image.save(name+'.png')
          PY
        ''}
        mkdir "$out"
        cp compile.log test.log diagnostic.bin evidence.json "$out/"
        ${lib.optionalString video ''cp video-green.ppm video-red.ppm video-green.png video-red.png "$out/"''}
        ${lib.optionalString audio ''cp lynx-stereo.wav "$out/"''}
        ln -s ${source} "$out/source"
        ln -s ${lynxHdl} "$out/console-hdl"
        verilator --version > "$out/tool-version.txt"
      '';
  coreCheck = coreIntegration false false;
  videoCoreCheck = coreIntegration true false;
  avCoreCheck = coreIntegration true true;
  videoFifoCheck =
    runCommand "chipbuilder-video-fifo-check"
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
        cp ${../hardware/video/cb_sync_fifo.sv} cb_sync_fifo.sv
        verilator --cc --exe --build -j 4 -Wall --top-module cb_sync_fifo --Mdir obj \
          -CFLAGS '-O2 -std=c++17' cb_sync_fifo.sv ${../sim/video-fifo.cpp} \
          > compile.log 2>&1 || { tail -80 compile.log; exit 1; }
        ./obj/Vcb_sync_fifo > test.log 2>&1 || { cat test.log; exit 1; }
        cat test.log
        yosys -Q -T -p 'read_verilog -sv cb_sync_fifo.sv; synth_gowin -family gw2a -top cb_sync_fifo -noiopads -json fifo.json; stat' \
          > synthesis.log 2>&1 || { tail -80 synthesis.log; exit 1; }
        python - <<'PY'
        import collections,json
        netlist=json.load(open('fifo.json'))
        cells=collections.Counter(c['type'] for c in netlist['modules']['cb_sync_fifo']['cells'].values())
        brams=sum(cells[t] for t in ['DPB','SDPB','DPX9B','SDPX9B'])
        assert 1<=brams<=2, f'FIFO did not map within two block RAMs: {dict(cells)}'
        assert not any('LATCH' in t.upper() for t in cells), 'Unintended latch'
        json.dump({'scope':'32-bit, 257-entry same-clock FIFO; not complete video or physical acceptance',
                   'block_rams':brams,'mapped_cells':dict(cells),'passed':True},open('evidence.json','w'),indent=2)
        print('PASS: FIFO mapped to',brams,'Gowin block RAM(s)')
        PY
        mkdir "$out"
        cp compile.log test.log synthesis.log fifo.json evidence.json "$out/"
        yosys -V > "$out/yosys-version.txt"
        verilator --version > "$out/verilator-version.txt"
      '';
  frameCaptureCheck =
    runCommand "chipbuilder-frame-capture-check"
      {
        nativeBuildInputs = [
          verilator
          stdenv.cc
          gnumake
          python3
        ];
      }
      ''
        cp ${../hardware/video/cb_sync_fifo.sv} cb_sync_fifo.sv
        cp ${../hardware/video/lynx_frame_capture.sv} lynx_frame_capture.sv
        verilator --cc --exe --build -j 4 -Wall --top-module lynx_frame_capture --Mdir obj \
          -CFLAGS '-O2 -std=c++17' cb_sync_fifo.sv lynx_frame_capture.sv ${../sim/frame-capture.cpp} \
          > compile.log 2>&1 || { tail -80 compile.log; exit 1; }
        ./obj/Vlynx_frame_capture > test.log 2>&1 || { cat test.log; exit 1; }
        cat test.log
        mkdir "$out"
        cp compile.log test.log "$out/"
        verilator --version > "$out/verilator-version.txt"
      '';
  videoPipelineCheck =
    runCommand "chipbuilder-video-pipeline-check"
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
        verilator --cc --exe --build -j 4 -Wall -Wno-DECLFILENAME -Wno-PROCASSINIT --top-module tang_video_top --Mdir obj \
          -CFLAGS '-O2 -std=c++17' ${videoSource}/hardware/video/*.sv \
          ${videoSource}/hardware/tang/cb_memory_arbiter.sv ${videoSource}/hardware/tang/lynx_sdram.sv \
          ${videoSource}/hardware/tests/tang-video-top.sv ${videoSource}/sim/video-pipeline.cpp \
          > compile.log 2>&1 || { tail -100 compile.log; exit 1; }
        ./obj/Vtang_video_top evidence.json > test.log 2>&1 || { cat test.log; exit 1; }
        cat test.log
        yosys -Q -T -p 'read_verilog -sv ${videoSource}/hardware/video/*.sv; synth_gowin -family gw2a -top lynx_scanout -noiopads -json scanout.json; stat' \
          > synthesis.log 2>&1 || { tail -100 synthesis.log; exit 1; }
        python - <<'PY'
        import collections,json
        netlist=json.load(open('scanout.json'))
        cells=collections.Counter(c['type'] for c in netlist['modules']['lynx_scanout']['cells'].values())
        brams=sum(cells[t] for t in ['DPB','SDPB','DPX9B','SDPX9B'])
        assert 1<=brams<=2, f'Line buffer RAM inference failed: {dict(cells)}'
        assert not any('LATCH' in t.upper() for t in cells), 'Unintended latch'
        json.dump({'scope':'scanout component only; no full-board route/physical timing', 'block_rams':brams,
                   'mapped_cells':dict(cells),'passed':True},open('synthesis.json','w'),indent=2)
        print('PASS: line buffers mapped to',brams,'Gowin block RAM(s)')
        PY
        mkdir "$out"
        cp compile.log test.log evidence.json synthesis.log synthesis.json scanout.json "$out/"
        ln -s ${videoSource} "$out/source"
        verilator --version > "$out/verilator-version.txt"
        yosys -V > "$out/yosys-version.txt"
      '';
  systemMapping =
    audio:
    runCommand "chipbuilder-tang-portable-${if audio then "av" else "system"}-sizing"
      {
        nativeBuildInputs = [
          yosys
          python3
        ];
      }
      ''
        yosys -Q -T -p 'read_verilog ${lynxHdl}/lynx-compact.v; read_verilog -sv ${rtlSource}/hardware/tang/*.sv ${rtlSource}/hardware/video/*.sv ${rtlSource}/hardware/audio/*.sv; chparam -set VIDEO 1 -set AUDIO ${if audio then "1" else "0"} lynx_tang_system; synth_gowin -family gw2a -top lynx_tang_system -noiopads -json system.json; stat' \
          > synthesis.log 2>&1 || { tail -100 synthesis.log; exit 1; }
        python - <<'PY'
        import collections,json
        cells=collections.Counter(c['type'] for c in json.load(open('system.json'))['modules']['lynx_tang_system']['cells'].values())
        brams=sum(cells[t] for t in ['DPB','SDPB','DPX9B','SDPX9B'])
        registers=sum(n for t,n in cells.items() if t.startswith('DFF'))
        assert 33<brams<=46, f'Integrated RAM mapping: {dict(cells)}'
        assert registers<=15552, 'Mapped register capacity exceeded'
        assert not any('LATCH' in t.upper() for t in cells), 'Unintended latch'
        result={'scope':'portable Lynx console plus UART/loader/cart, frame capture, arbiter, SDRAM and dual-clock RGB scanout; mapped primitives only',
                'audio_included':${if audio then "True" else "False"},
                'mapped_cells':dict(cells),'block_rams':brams,'registers':registers,
                'lut1_to_lut4_cells':sum(cells[f'LUT{i}'] for i in range(1,5)),
                'alu_cells':cells['ALU'],'place_and_route_passed':False,'board_timing_signoff':False,
                'omitted':['clock generation/reset synchronizers','pin/IO buffers','HDMI serializer']+${
                  if audio then "[]" else "['audio transport']"
                },
                'passed_synthesis_checks':True}
        json.dump(result,open('evidence.json','w'),indent=2)
        print('PASS: portable system mapped,',brams,'block RAMs,',registers,'registers; full board fit/timing not established')
        PY
        mkdir "$out"
        cp synthesis.log system.json evidence.json "$out/"
        ln -s ${rtlSource} "$out/source"
        ln -s ${lynxHdl} "$out/console-hdl"
        yosys -V > "$out/yosys-version.txt"
      '';
  systemSizing = systemMapping false;
  avSizing = systemMapping true;
in
{
  inherit
    servicesCheck
    hostCheck
    host
    coreCheck
    videoCoreCheck
    avCoreCheck
    videoFifoCheck
    frameCaptureCheck
    videoPipelineCheck
    systemSizing
    audioCheck
    avSizing
    ;
}
