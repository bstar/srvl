{
  description = "Chipbuilder: tools for a Lynx-inspired custom handheld";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.mister-template = {
    url = "github:MiSTer-devel/Template_MiSTer/5dda37366d02b04b8448da7b322235c1831af811";
    flake = false;
  };
  inputs.cpu-core = {
    url = "github:freecores/cpu65c02_true_cycle/acd38f0ec29facbf7a0d6c144b20a4757bfc0358";
    flake = false;
  };
  inputs.cpu-tests = {
    url = "github:Klaus2m5/6502_65C02_functional_tests/7954e2dbb49c469ea286070bf46cdd71aeb29e4b";
    flake = false;
  };
  inputs.lynx-reference = {
    url = "github:MiSTer-devel/AtariLynx_MiSTer/3708e457e413aa7a33f8bec8fcd79eba45ce4702";
    flake = false;
  };

  outputs =
    {
      self,
      nixpkgs,
      mister-template,
      cpu-core,
      cpu-tests,
      lynx-reference,
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfreePredicate =
          pkg:
          builtins.elem (nixpkgs.lib.getName pkg) [
            "chipbuilder-quartus-lite"
            "chipbuilder-quartus-runtime"
            "Quartus-lite"
          ];
      };
      quartus = pkgs.callPackage ./nix/quartus.nix { };
      software = pkgs.callPackage ./nix/software.nix {
        cpuSource = cpu-core;
        testSource = cpu-tests;
      };
      lynxAudit = pkgs.callPackage ./nix/lynx-audit.nix {
        source = lynx-reference;
        inherit quartus;
      };
      tools = with pkgs; [
        verilator
        iverilog
        ghdl
        yosys
        gtkwave
        cc65
        python3
        gnumake
        git
        openssh
        pkg-config
        SDL2
      ];
      simulation =
        long:
        pkgs.runCommand "chipbuilder-prototype-simulation${pkgs.lib.optionalString long "-full"}"
          {
            nativeBuildInputs = [
              pkgs.verilator
              pkgs.stdenv.cc
              pkgs.gnumake
              pkgs.python3
            ];
          }
          ''
            export HOME="$TMPDIR"
            verilator --binary --timing --top-module demo_tb \
              --Mdir obj_dir ${./hardware/rtl/chipbuilder_demo.sv} ${./hardware/tests/demo_tb.sv} > compile.log 2>&1 || { cat compile.log; exit 1; }
            ./obj_dir/Vdemo_tb ${pkgs.lib.optionalString long "+long"} > simulation.log 2>&1 || { cat simulation.log; exit 1; }
            cat simulation.log
            mkdir -p "$out"
            cp compile.log simulation.log "$out/"
            python ${./scripts/preview-to-png.py} preview.ppm "$out/preview.png"
          '';
    in
    {
      devShells.${system} = {
        default = pkgs.mkShell {
          packages = tools;
          shellHook = ''
            export CHIPBUILDER_ROOT="$PWD"
            export XDG_CACHE_HOME="$PWD/.cache"
            echo "Chipbuilder: HDL simulation and 65C02 tools (Nix)."
          '';
        };
        quartus = pkgs.mkShell {
          packages = [
            quartus
            pkgs.python3
          ];
          shellHook = ''
            export XDG_CACHE_HOME="$PWD/.cache"
            echo "Chipbuilder: Quartus Lite 17.0.2.602, Cyclone V."
          '';
        };
        ecp5 = pkgs.mkShell {
          packages = tools ++ [
            pkgs.nextpnr
            pkgs.trellis
            pkgs.openfpgaloader
          ];
          shellHook = ''
            export CHIPBUILDER_ROOT="$PWD"
            export XDG_CACHE_HOME="$PWD/.cache"
            echo "Chipbuilder: ECP5-12F development tools; no board is programmed automatically."
          '';
        };
        tang = pkgs.mkShell {
          packages = tools ++ [
            pkgs.nextpnr
            pkgs.python3Packages.apycula
            pkgs.openfpgaloader
          ];
          shellHook = ''
            export CHIPBUILDER_ROOT="$PWD"
            export XDG_CACHE_HOME="$PWD/.cache"
            echo "Chipbuilder: Gowin/Tang audit tools; no board is programmed automatically."
          '';
        };
      };
      packages.${system} = {
        inherit quartus;
        inherit (software) cpu-hdl cpu-check cpu-functional;
        inherit (software) simulator simulator-equivalence game-data;
        lynx-audit-hdl = lynxAudit.hdl;
        lynx-audit-sizing = lynxAudit.sizing;
        lynx-audit-smoke = lynxAudit.smoke;
        lynx-audit-report = lynxAudit.report;
        lynx-audit-route-probe = lynxAudit.routeProbe;
        lynx-audit-ram-check = lynxAudit.ramCheck;
        lynx-compatibility-audit = lynxAudit.audit;
        standalone-cpu-sizing =
          pkgs.runCommand "chipbuilder-standalone-cpu-sizing"
            {
              nativeBuildInputs = [
                pkgs.yosys
                pkgs.python3
              ];
            }
            ''
              mkdir -p "$out"
              yosys -Q -T -p 'read_verilog ${software.cpu-hdl}/cpu.v; synth_ecp5 -top core -json cpu.json; stat' > "$out/synthesis.log" 2>&1
              python ${./scripts/check-standalone-budget.py} ${./hardware/targets/standalone.json} \
                --cpu-netlist cpu.json --report "$out/budget.json"
              cp cpu.json "$out/"
              yosys -V > "$out/tool-version.txt"
            '';
        simulation-full = simulation true;
        prototype =
          pkgs.runCommand "chipbuilder-mister-prototype"
            {
              nativeBuildInputs = [
                quartus
                pkgs.python3
              ];
              project = pkgs.lib.fileset.toSource {
                root = ./.;
                fileset = pkgs.lib.fileset.unions [
                  ./hardware/rtl/chipbuilder_demo.sv
                  ./hardware/mister/Chipbuilder.sv
                  ./scripts/prepare-mister.py
                  ./scripts/check-timing.tcl
                ];
              };
            }
            ''
              export HOME="$TMPDIR/home"
              mkdir -p "$HOME"
              python "$project/scripts/prepare-mister.py" ${mister-template} "$project" "$TMPDIR/mister-build"
              cd "$TMPDIR/mister-build"
              if ! quartus_sh --flow compile Chipbuilder > quartus.log 2>&1; then
                tail -100 quartus.log
                exit 1
              fi
              if ! quartus_sta -t "$project/scripts/check-timing.tcl" Chipbuilder > timing-check.log 2>&1; then
                cat timing-check.log
                exit 1
              fi
              test -s output_files/Chipbuilder.rbf
              mkdir -p "$out/reports"
              cp output_files/Chipbuilder.rbf "$out/Chipbuilder.rbf"
              cp output_files/*.rpt "$out/reports/"
              cp quartus.log "$out/reports/"
              cp timing-check.log prototype-*.rpt "$out/reports/"
              cp LICENSE.MiSTer "$out/"
              cd "$out"
              sha256sum Chipbuilder.rbf > sha256.txt
            '';
      };
      apps.${system}.sim = {
        type = "app";
        program = "${software.simulator}/bin/chipbuilder-sim";
        meta.description = "Play Circuit Courier on the Chipbuilder HDL prototype";
      };
      formatter.${system} = pkgs.writeShellApplication {
        name = "chipbuilder-fmt";
        runtimeInputs = [ pkgs.nixfmt ];
        text = ''
          exec nixfmt "$@" flake.nix nix/quartus.nix nix/software.nix nix/lynx-audit.nix
        '';
      };
      checks.${system} = {
        lynx-diagnostic = lynxAudit.smoke;
        standalone-budget = self.packages.${system}.standalone-cpu-sizing;
        cpu = software.cpu-directed;
        peripherals = software.peripheral-check;
        game = software.game-check;
        prototype = simulation false;
        toolchain =
          pkgs.runCommand "chipbuilder-toolchain-check"
            {
              nativeBuildInputs = tools ++ [ pkgs.stdenv.cc ];
            }
            ''
              export HOME="$TMPDIR"
              export XDG_CACHE_HOME="$TMPDIR/.cache"
              cp -r ${./checks} fixtures
              chmod -R u+w fixtures
              cd fixtures
              bash smoke.sh
              touch "$out"
            '';
        documentation =
          pkgs.runCommand "chipbuilder-documentation-check"
            {
              nativeBuildInputs = [ pkgs.python3 ];
            }
            ''
              python ${./scripts/check-docs.py} ${self}
              touch "$out"
            '';
      };
    };
}
