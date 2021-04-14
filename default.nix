{ pkgs ? import <nixpkgs> {} }:
{
  shell = pkgs.mkShell {
    buildInputs = with pkgs; [ zig qemu gdb socat (writeScriptBin "enter-qemu-monitor" ''
      #!${stdenv.shell}
      socat -,echo=0,icanon=0 unix-connect:qemu-monitor-socket
    '')];
    OVMF_FW_CODE_PATH = "${pkgs.OVMF.fd}/FV/OVMF_CODE.fd";
  };
}
