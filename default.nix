{ pkgs ? import <nixpkgs> {} }:
{
  shell = pkgs.mkShell {
    buildInputs = with pkgs; [ raito-dev.zig qemu lldb gdb ];
    OVMF_FW_CODE_PATH = "${pkgs.OVMF.fd}/FV/OVMF_CODE.fd";
  };
}
