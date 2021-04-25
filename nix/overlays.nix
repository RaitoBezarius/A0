self: super: {
  edk2 = self.callPackage ./edk2.nix {};
  OVMF = (super.OVMF.override { inherit (self) edk2; }).overrideAttrs (old: {
    buildPhase = ''
      runHook preBuild
      build -a X64 -b DEBUG -t GCC5 -p OvmfPkg/OvmfPkgX64.dsc -n $NIX_BUILD_CORES $buildFlags
      runHook postBuild
    '';
  });
}
