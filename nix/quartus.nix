{
  lib,
  stdenv,
  fetchurl,
  unstick,
  unzip,
  buildFHSEnv,
  writeShellScriptBin,
  symlinkJoin,
}:
let
  installerEnv = buildFHSEnv {
    name = "srvl-quartus-installer";
    targetPkgs =
      p: with p; [
        bash
        coreutils
        findutils
        unzip
        unstick
        python3
      ];
    multiPkgs =
      p: with p; [
        glibc
        gcc.cc.lib
        zlib
        libx11
        libxext
        libxrender
        libice
        libsm
        libxft
        fontconfig
        freetype
        ncurses5
        libxcrypt-legacy
      ];
    multiArch = true;
    runScript = "bash";
  };
  # Official vendor SHA-1: archive integrity pin, not a newly measured SHA-256.
  # See docs/research/tooling.md for download provenance and compatibility notes.
  archive = fetchurl {
    name = "Quartus-lite-17.0.2.602-linux.tar";
    sha1 = "02aebab728d54e3ca8660d2646fdf93bc669b0ac";
    url = "https://download.altera.com/akdlm/software/acdsinst/17.0std.2/602/ib_tar/Quartus-lite-17.0.2.602-linux.tar";
    curlOptsList = [
      "--user-agent"
      "Alterabot/1.0"
    ];
  };
  unwrapped = stdenv.mkDerivation {
    pname = "srvl-quartus-lite";
    version = "17.0.2.602";
    src = archive;
    nativeBuildInputs = [
      unstick
      unzip
    ];
    dontUnpack = true;
    dontFixup = true;
    # The archive includes base installers, device data and Update 2. Isolate only
    # the base Lite installer and Cyclone V data so optional products aren't installed.
    installPhase = ''
      runHook preInstall
      mkdir selected
      tar -xf "$src" -C selected --strip-components=1 \
        components/QuartusLiteSetup-17.0.0.595-linux.run \
        components/QuartusSetup-17.0.2.602-linux.run \
        components/cyclonev-17.0.0.595.qdz
      chmod u+w,+x selected/*.run
      # These 17.0 installers are static self-extracting executables, unlike newer
      # Quartus installers. Their missing section tables must not be patchelf'ed.
      export HOME="$TMPDIR/home"
      mkdir -p "$HOME"
      ${installerEnv}/bin/srvl-quartus-installer -c \
        'python3 "$1" "$2" --mode unattended --installdir "$3" --disable-components quartus_help,arria_lite,cyclone,cyclone10lp,max,max10,quartus_update,modelsim_ase,modelsim_ae' \
        -- ${./run-quartus-installer.py} "$PWD/selected/QuartusLiteSetup-17.0.0.595-linux.run" "$out"
      ${installerEnv}/bin/srvl-quartus-installer -c \
        'python3 "$1" "$2" --mode unattended --installdir "$3"' \
        -- ${./run-quartus-installer.py} "$PWD/selected/QuartusSetup-17.0.2.602-linux.run" "$out"
      test -x "$out/quartus/bin/quartus_sh"
      test -d "$out/quartus/common/devinfo/cyclonev"
      rm -rf "$out/uninstall" "$out/logs"
      runHook postInstall
    '';
    meta = {
      description = "MiSTer Quartus Lite 17.0.2.602 with Cyclone V device support";
      license = lib.licenses.unfree;
      platforms = [ "x86_64-linux" ];
    };
  };
  runtime = buildFHSEnv {
    name = "srvl-quartus-runtime";
    targetPkgs =
      p: with p; [
        bash
        coreutils
        zlib
        bzip2
        expat
        glib
        fontconfig
        freetype
        libx11
        libxext
        libxrender
        libxtst
        libxi
        libxft
        libice
        libsm
        libxau
        libxdmcp
        libxscrnsaver
        libudev0-shim
        libxcrypt-legacy
        ncurses5
        libxml2
        unixodbc
        dejavu_fonts
      ];
    runScript = "bash";
    profile = ''
      export QUARTUS_ROOTDIR=${unwrapped}/quartus
      export QUARTUS_ROOTDIR_OVERRIDE="$QUARTUS_ROOTDIR"
      export SOPC_KIT_NIOS2=${unwrapped}/nios2eds
      export QT_QPA_PLATFORM=xcb
      export PATH=${unwrapped}/quartus/bin:$PATH
    '';
    meta.license = lib.licenses.unfree;
  };
  commands = [
    "quartus"
    "quartus_sh"
    "quartus_map"
    "quartus_fit"
    "quartus_asm"
    "quartus_sta"
    "quartus_cpf"
    "quartus_pgm"
  ];
in
symlinkJoin {
  name = "srvl-quartus-lite-17.0.2.602";
  paths = map (
    command:
    writeShellScriptBin command ''
      exec ${runtime}/bin/srvl-quartus-runtime -c \
        'exec "$QUARTUS_ROOTDIR/bin/${command}" "$@"' ${command} "$@"
    ''
  ) commands;
  passthru = { inherit unwrapped archive; };
  meta = {
    description = "Project-local Quartus Lite 17.0.2.602 commands";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
  };
}
