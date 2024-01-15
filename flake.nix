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





  #   packages.armv7l-linux = let
  #     platforms = (import nixpkgs { config = {}; }).platforms;
  #     eval = (import ./default.nix {
  #       extraModules = [
  #         ./rpi_image.nix
  #         { system.build.rpi_firmware = firmware; }
  #       ];
  #       platform = system: platforms.raspberrypi2;
  #       system = "x86_64-linux";
  #       crossSystem.system = "armv7l-linux";
  #       inherit nixpkgs;
  #     });
  #     zynq_eval = (import ./. {
  #       extraModules = [
  #         ./zynq_image.nix
  #       ];
  #       system = "x86_64-linux";
  #       crossSystem.system = "armv7l-linux";
  #       inherit nixpkgs;
  #     });
  #   in {
  #     rpi_image = eval.config.system.build.rpi_image;
  #     rpi_image_tar = eval.config.system.build.rpi_image_tar;
  #     toplevel = eval.config.system.build.toplevel;
  #     zynq_image = zynq_eval.config.system.build.zynq_image;
  #   };
  #   hydraJobs = {
  #     armv7l-linux = {
  #       rpi_image_tar = self.packages.armv7l-linux.rpi_image_tar;
  #       zynq_image = self.packages.armv7l-linux.zynq_image;
  #     };
  #   };
  # };

