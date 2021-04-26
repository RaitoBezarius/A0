{ pkgs ? import <nixpkgs> {
  overlays = [ (import ./nix/overlays.nix) ]; # Patch EDK2 & OVMF
} }:
let
  OVMF = pkgs.OVMF;
  local-qemu = (pkgs.qemu.overrideAttrs (old: {
    src = ./vendor/qemu;
  }));
  raito-pkgs = import (fetchTarball {
    url = "https://github.com/RaitoBezarius/nixexprs/archive/f37bce8a179b86d2b062116e18d61f0628be8c70.tar.gz";
    sha256 = "0ys6ha8dxbbibynjpsiqmb50d9dpb2lpmfi20ray49jyamp5fxix";
  }) { inherit pkgs; };
  pePythonEnv = pkgs.python3.withPackages (ps: with ps; [ pefile ]);
  generate-symbols-script = pkgs.writeScriptBin "print-debug-script-for-ovmf" 
    ''
      #!${pkgs.stdenv.shell}
      LOG=''${1:-build/debug.log}
      BUILD=''${2:-${OVMF}/X64}
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
    CACHE_NAME = "a0-kernel";
    inputsFrom = [ local-qemu ];
    nativeBuildInputs = with pkgs; [
      OVMF
    ];
    buildInputs = with pkgs; [
      cachix qemu
      raito-pkgs.zig
      gdb socat radare2 rr
      (writeScriptBin "enter-qemu-monitor" ''
      #!${stdenv.shell}
      socat -,echo=0,icanon=0 unix-connect:qemu-monitor-socket
    '')
    (writeScriptBin "push-shell-to-cachix" ''
      #!${stdenv.shell}
      nix-store --query --references $(nix-instantiate shell.nix) | \
      xargs nix-store --realise | xargs nix-store --query --requisites | cachix push $CACHE_NAME
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
    OVMF_FW_CODE_PATH = "${(pkgs.enableDebugging OVMF).fd}/FV/OVMF_CODE.fd";
    OVMF_BASE = "${OVMF}/X64";
  };
}
