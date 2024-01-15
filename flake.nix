{
  inputs.nixpkgs.url = github:NixOS/nixpkgs/nixos-unstable;

  outputs = { self, nixpkgs }:
    let
      pkgs = import nixpkgs { system = "x86_64-linux"; };
      not-os-cfg = not-os-configured.config.system;

      not-os-configured = (import ./. {
        inherit nixpkgs;
        extraModules = [
          ./zynq_image.nix
        ];
        system = "x86_64-linux";
        crossSystem.system = "armv7l-linux";
      });
    in {
      packages.armv7l-linux = {
        zc706-not-os = not-os-cfg.build.zynq_image;
        zc706-sd-image = not-os-cfg.build.sd-image;
      };
    };
}

