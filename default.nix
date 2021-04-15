{ pkgs ? import <nixpkgs> {} }:
let
  uefiWithDebug = pkgs.OVMF.overrideAttrs (old: {
    buildPhase = ''
      runHook preBuild
      build -a X64 -b DEBUG -t GCC5 -p OvmfPkg/OvmfPkgX64.dsc -n $NIX_BUILD_CORES $buildFlags
      runHook postBuild
    '';
  });
  pePythonEnv = pkgs.python3.withPackages (ps: with ps; [ pefile ]);
  generate-symbols-script = pkgs.writeScriptBin "print-debug-script-for-ovmf" 
    ''
      #!${pkgs.stdenv.shell}
      LOG=''${1:-build/debug.log}
      BUILD=''${2:-${uefiWithDebug}/X64}
      SEARCHPATHS="''${BUILD} build/EFI/BOOT"

      cat ''${LOG} | grep Loading | grep -i efi | while read LINE; do
        BASE="`echo ''${LINE} | cut -d " " -f4`"
        NAME="`echo ''${LINE} | cut -d " " -f6 | tr -d "[:cntrl:]"`"
        EFIFILE="`find ''${SEARCHPATHS} -name ''${NAME} -maxdepth 1 -type f`"
        ADDR="`${pePythonEnv}/bin/python3 contrib/extract_text_va.py ''${EFIFILE} 2>/dev/null`"
        [ ! -z "$ADDR" ] && TEXT="`${pkgs.python3}/bin/python -c "print(hex(''${BASE} + ''${ADDR}))"`"
        SYMS="`echo ''${NAME} | sed -e "s/\.efi/\.debug/g"`"
        SYMFILE="`find ''${SEARCHPATHS} -name ''${SYMS} -maxdepth 1 -type f`"
        [ ! -z "$ADDR" ] && echo "add-symbol-file ''${SYMFILE} ''${TEXT}"
      done
    '';
in
{
  shell = pkgs.mkShell {
    buildInputs = with pkgs; [ raito-dev.zig qemu gdb socat radare2 rr
      (writeScriptBin "enter-qemu-monitor" ''
      #!${stdenv.shell}
      socat -,echo=0,icanon=0 unix-connect:qemu-monitor-socket
    '')
    generate-symbols-script
    (writeScriptBin "sgdb" ''
      #!${stdenv.shell}
      echo "[+] Generating symbols for OVMF and the kernel, this might take a while..."
      ${generate-symbols-script}/bin/print-debug-script-for-ovmf > /tmp/a0-gdbscript
      echo "set substitute-path /build/edk2 ./ovmf-src" >> /tmp/a0-gdbscript
      gdb -x /tmp/a0-gdbscript
    '')
    (writeScriptBin "fsgdb" ''
      #!${stdenv.shell}
      echo "Cached gdbscript, rerun sgdb to recompute the offsets if needed."
      gdb -x /tmp/a0-gdbscript
    '')
    ];
    OVMF_FW_CODE_PATH = with pkgs; "${(enableDebugging uefiWithDebug).fd}/FV/OVMF_CODE.fd";
    OVMF_BASE = "${uefiWithDebug}/X64";
  };
}
