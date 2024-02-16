{ lib, config, pkgs, ... }:

with lib;
let
  # dont use overlays for the qemu, it causes a lot of wasted time on recompiles
  x86pkgs = import pkgs.path { system = "x86_64-linux"; };
  crosspkgs = import pkgs.path {
    system = "x86_64-linux";
    crossSystem = {
      system = "armv7l-linux";
      linux-kernel = {
        name = "zynq";
        baseConfig = "multi_v7_defconfig";
        target = "uImage";
        installTarget = "uImage";
        autoModules = false;
        DTB = true;
        makeFlags = [ "LOADADDR=0x8000" ];
      };
    };
  };
  customKernel = (crosspkgs.linux.override {
    extraConfig = ''
      OVERLAY_FS y
      MEDIA_SUPPORT n
      FB n
      DRM n
      SOUND n
      SQUASHFS n
      BACKLIGHT_CLASS_DEVICE n
    '';
  }).overrideAttrs (oldAttrs: {
    postInstall = ''
      cp arch/arm/boot/uImage $out
      ${oldAttrs.postInstall}
    '';
  });
  customKernelPackages = crosspkgs.linuxPackagesFor customKernel;
in {
  imports = [ ./arm32-cross-fixes.nix ];
  boot.kernelPackages = customKernelPackages;
  boot.postBootCommands = lib.mkIf config.not-os.sd ''

    if [ -f /nix-path-registration ]; then
      set -x
      set -euo pipefail

      rootPart=$(${pkgs.utillinux}/bin/findmnt -n -o SOURCE /)
      bootDevice=$(lsblk -npo PKNAME $rootPart)
      partNum=$(lsblk -npo MAJ:MIN $rootPart | ${pkgs.gawk}/bin/awk -F: '{print $2}')

      echo ",+," | sfdisk -N$partNum --no-reread $bootDevice
      ${pkgs.parted}/bin/partprobe
      ${pkgs.e2fsprogs}/bin/resize2fs $rootPart
 
      nix-store --load-db < /nix-path-registration

      touch /etc/NIXOS
      nix-env -p /nix/var/nix/profiles/system --set /run/current-system

      rm -f /nix-path-registration
    fi


  '';
  nixpkgs.system = "armv7l-linux";
  networking.hostName = "zynq";
  not-os.sd = true;
  not-os.simpleStaticIp = true;
  environment = {
    systemPackages = with pkgs; [ inetutils wget nano ];
    etc = {
      "service/getty/run".source = pkgs.writeShellScript "getty" ''
        hostname ${config.networking.hostName}
        exec setsid agetty ttyPS0 115200
      '';
      "pam.d/other".text = ''
        auth     sufficient pam_permit.so
        account  required pam_permit.so
        password required pam_permit.so
        session  optional pam_env.so
      '';
      "security/pam_env.conf".text = "";
    };
  };
}
