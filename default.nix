{ pkgs ? import <nixpkgs> {} }:
{
  shell = pkgs.mkShell {
    buildInputs = with pkgs; [ zig qemu ];
    OVMF_FW_CODE_PATH = "${pkgs.OVMF.fd}/FV/OVMF_CODE.fd";
  };
}
