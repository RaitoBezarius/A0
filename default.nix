{ pkgs ? import <nixpkgs> {} }:
{
  shell = pkgs.mkShell {
    buildInputs = with pkgs; [ zig qemu ];
  };
}
