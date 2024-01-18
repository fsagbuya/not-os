{ lib, config, pkgs, ... }:

with lib;
let
  # dont use overlays for the qemu, it causes a lot of wasted time on recompiles
  x86pkgs = import pkgs.path { system = "x86_64-linux"; };
  qemu = x86pkgs.qemu.overrideAttrs (oldAttrs: rec {
    version = "8.1.3";
    src = pkgs.fetchurl {
      url = "https://download.qemu.org/qemu-${version}.tar.xz";
      hash = "sha256-Q8wXaAQQVYb3T5A5jzTp+FeH3/QA07ZA2B93efviZbs=";
    };
  });
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
    '';
  }).overrideAttrs (oldAttrs: {
    postInstall = ''
      cp arch/arm/boot/uImage $out
      ${oldAttrs.postInstall}
    '';
  });
  customKernelPackages = crosspkgs.linuxPackagesFor customKernel;

  sd-image = let
    rootfsImage = x86pkgs.callPackage (pkgs.path + "/nixos/lib/make-ext4-fs.nix") {
      storePaths = [ config.system.build.toplevel ];
      volumeLabel = "ROOT";
      compressImage = true;
    };
    firmwarePartitionOffset = 8;
    firmwareSize = 30;
    in pkgs.stdenv.mkDerivation {
      name = "sd-image";
      nativeBuildInputs = with x86pkgs; [ dosfstools e2fsprogs mtools libfaketime util-linux zstd parted ];
      buildCommand = ''
        mkdir -p $out/sd-image
        export img=$out/sd-image/sd-image.img

        echo "Decompressing rootfs image"
        zstd -d --no-progress "${rootfsImage}" -o ./root-fs.img

        gap=${toString firmwarePartitionOffset}

        rootSizeBlocks=$(du -B 512 --apparent-size $root_fs | awk '{ print $1 }')
        firmwareSizeBlocks=$((${toString firmwareSize} * 1024 * 1024 / 512))
        imageSize=$((rootSizeBlocks * 512 + firmwareSizeBlocks * 512 + gap * 1024 * 1024))
        truncate -s $imageSize $img

        parted $img mklabel msdos
        parted $img mkpart primary fat32 8MB 38MB
        parted $img mkpart primary ext4 38MB 100%
        parted $img set 1 boot on

        eval $(partx $img -o START,SECTORS --nr 2 --pairs)
        dd conv=notrunc if=./root-fs.img of=$img seek=$START count=$SECTORS

        eval $(partx $img -o START,SECTORS --nr 1 --pairs)
        truncate -s $((SECTORS * 512)) firmware_part.img
        faketime "1970-01-01 00:00:00" mkfs.vfat -n BOOT firmware_part.img

        mkdir firmware
        cp ${config.system.build.kernel}/uImage firmware/
        cp ${config.system.build.uRamdisk}/initrd firmware/uramdisk.image.gz
        cp ${config.system.build.kernel}/dtbs/zynq-zc706.dtb firmware/devicetree.dtb
        
        (cd firmware; mcopy -psvm -i ../firmware_part.img ./* ::)

        fsck.vfat -vn firmware_part.img
        dd conv=notrunc if=firmware_part.img of=$img seek=$START count=$SECTORS
      '';
    };
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
  system.build.sd-image = sd-image;
  not-os.sd = true;
  not-os.simpleStaticIp = true;
  system.build.zynq_image = let
    cmdline = "root=/dev/mmcblk0p2 console=ttyPS0,115200n8 systemConfig=${builtins.unsafeDiscardStringContext config.system.build.toplevel}";
    qemuScript = ''
      #!/bin/bash
      export PATH=${qemu}/bin:$PATH
      BASE=$(realpath $(dirname $0))

      PERSISTENT_DIR="/home/flo/qemu_persistent_dir"
      mkdir -p "$PERSISTENT_DIR"
      OVERLAY_IMG="$PERSISTENT_DIR/sd-overlay.qcow2"

      if [ ! -f "$OVERLAY_IMG" ]; then
        qemu-img create -F raw -f qcow2 -b $BASE/sd-image.img $OVERLAY_IMG 512M
      fi

      qemu-system-arm \
        -M xilinx-zynq-a9 \
        -serial /dev/null \
        -serial stdio \
        -display none \
        -dtb $BASE/devicetree.dtb \
        -kernel $BASE/uImage \
        -initrd $BASE/uramdisk.image.gz \
        -drive file=$OVERLAY_IMG,if=sd,format=qcow2 \
        -net nic -net nic -net user,hostfwd=tcp::1114-:22 \
        -append "${cmdline}"

    '';
  in pkgs.runCommand "zynq_image" {
    inherit qemuScript;
    passAsFile = [ "qemuScript" ];
    preferLocalBuild = true;
  } ''
    mkdir $out
    cd $out
    cp -s ${config.system.build.sd-image}/sd-image/sd-image.img .
    cp -s ${config.system.build.squashfs} root.squashfs
    cp -s ${config.system.build.kernel}/uImage .
    cp -s ${config.system.build.uRamdisk}/initrd uramdisk.image.gz
    cp -s ${config.system.build.kernel}/dtbs/zynq-zc706.dtb devicetree.dtb
    ln -sv ${config.system.build.toplevel} toplevel
    cp $qemuScriptPath qemu-script
    chmod +x qemu-script
    patchShebangs qemu-script
    ls -ltrh
  '';
  environment = {
    systemPackages = with pkgs; [ inetutils wget ];
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
