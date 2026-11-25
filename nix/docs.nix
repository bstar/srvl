{
  lib,
  runCommand,
  python3,
  writeShellApplication,
}:
let
  python = python3.withPackages (ps: [ ps.markdown ]);
  source = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../README.md
      ../flake.nix
      ../flake.lock
      ../nix/docs.nix
      ../nix/tang.nix
      ../nix/tang-board.nix
      ../nix/tang-bitstream.nix
      ../nix/enhanced.nix
      ../nix/enhanced-system.nix
      ../docs
      ../hardware
      ../sim/README.md
      ../sim/sdram-model.hpp
      ../sim/tang-services.cpp
      ../sim/lynx-tang.cpp
      ../sim/frame-capture.cpp
      ../sim/video-pipeline.cpp
      ../sim/audio-output.cpp
      ../sim/audio-model.hpp
      ../sim/i2s-decoder.hpp
      ../sim/lynx-audio-monitor.hpp
      ../sim/dvi-encoder.cpp
      ../sim/tmds-model.hpp
      ../sim/board-control.cpp
      ../sim/scaled-blitter-model.hpp
      ../sim/scaled-blitter.cpp
      ../sim/scaled-blitter-memory.cpp
      ../sim/graphics-memory.cpp
      ../sim/native-graphics-model.hpp
      ../sim/blitter-mmio.cpp
      ../sim/native-graphics.cpp
      ../sim/enhanced-system.cpp
      ../tools
      ../checks
      ../patches
      ../firmware
      ../scripts
    ];
  };
  site = runCommand "chipbuilder-html-docs" { nativeBuildInputs = [ python ]; } ''
    python ${source}/scripts/build-docs.py ${source} "$out"
  '';
  check = runCommand "chipbuilder-html-docs-check" { nativeBuildInputs = [ python3 ]; } ''
    python ${source}/scripts/check-docs.py ${source}
    python ${source}/scripts/check-docsite.py ${site} ${source}
    touch "$out"
  '';
  server = writeShellApplication {
    name = "chipbuilder-docs";
    runtimeInputs = [ python3 ];
    text = ''
      port=8787
      if [[ $# -eq 2 && "$1" == "--port" && "$2" =~ ^[0-9]+$ ]]; then
        port="$2"
      elif [[ $# -ne 0 ]]; then
        echo "Usage: chipbuilder-docs [--port PORT]" >&2
        exit 2
      fi
      if (( port < 1 || port > 65535 )); then
        echo "PORT must be between 1 and 65535" >&2
        exit 2
      fi
      echo "Chipbuilder documentation: http://127.0.0.1:$port"
      echo "Repository snapshot; stop and rerun after source changes. Ctrl-C stops the server."
      exec python -m http.server "$port" --bind 127.0.0.1 --directory ${site}
    '';
  };
in
{
  inherit
    python
    site
    check
    server
    ;
}
