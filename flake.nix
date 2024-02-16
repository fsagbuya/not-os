{
  inputs.nixpkgs.url = github:NixOS/nixpkgs/nixos-unstable;

  outputs = { self, nixpkgs }:
    let
      pkgs = import nixpkgs { system = "x86_64-linux"; };
      not-os-cfg = not-os-configured.config.system;
      fsbl-support = ./fast-servo/fsbl-support;
      dts-support = ./fast-servo/dts-support;

      not-os-configured = (import ./. {
        inherit nixpkgs;
        extraModules = [
          ./zynq_image.nix
        ];
        system = "x86_64-linux";
        crossSystem.system = "armv7l-linux";
      });

      gnu-platform = "arm-none-eabi";
      binutils-pkg = { zlib, extraConfigureFlags ? [] }: pkgs.stdenv.mkDerivation rec {
        basename = "binutils";
        version = "2.30";
        name = "${basename}-${gnu-platform}-${version}";
        src = pkgs.fetchurl {
          url = "https://ftp.gnu.org/gnu/binutils/binutils-${version}.tar.bz2";
          sha256 = "028cklfqaab24glva1ks2aqa1zxa6w6xmc8q34zs1sb7h22dxspg";
        };
        configureFlags = [
          "--enable-deterministic-archives"
          "--target=${gnu-platform}"
          "--with-cpu=cortex-a9"
          "--with-fpu=vfpv3"
          "--with-float=hard"
          "--with-mode=thumb"
        ] ++ extraConfigureFlags;
        outputs = [ "out" "info" "man" ];
        depsBuildBuild = [ pkgs.buildPackages.stdenv.cc ];
        buildInputs = [ zlib ];
        enableParallelBuilding = true;
        meta = {
          description = "Tools for manipulating binaries (linker, assembler, etc.)";
          longDescription = ''
            The GNU Binutils are a collection of binary tools.  The main
            ones are `ld' (the GNU linker) and `as' (the GNU assembler).
            They also include the BFD (Binary File Descriptor) library,
            `gprof', `nm', `strip', etc.
          '';
          homepage = http://www.gnu.org/software/binutils/;
          license = pkgs.lib.licenses.gpl3Plus;
          /* Give binutils a lower priority than gcc-wrapper to prevent a
            collision due to the ld/as wrappers/symlinks in the latter. */
          priority = "10";
        };
      };

      gcc-pkg = { gmp, mpfr, libmpc, platform-binutils, extraConfigureFlags ? [] }: pkgs.stdenv.mkDerivation rec {
        basename = "gcc";
        version = "9.1.0";
        name = "${basename}-${gnu-platform}-${version}";
        src = pkgs.fetchurl {
          url = "https://ftp.gnu.org/gnu/gcc/gcc-${version}/gcc-${version}.tar.xz";
          sha256 = "1817nc2bqdc251k0lpc51cimna7v68xjrnvqzvc50q3ax4s6i9kr";
        };
        preConfigure = ''
          mkdir build
          cd build
        '';
        configureScript = "../configure";
        configureFlags = [ 
          "--target=${gnu-platform}"
          "--with-arch=armv7-a"
          "--with-tune=cortex-a9"
          "--with-fpu=vfpv3"
          "--with-float=hard"
          "--disable-libssp"
          "--enable-languages=c"
          "--with-as=${platform-binutils}/bin/${gnu-platform}-as"
          "--with-ld=${platform-binutils}/bin/${gnu-platform}-ld" ] ++ extraConfigureFlags;
        outputs = [ "out" "info" "man" ];
        hardeningDisable = [ "format" "pie" ];
        propagatedBuildInputs = [ gmp mpfr libmpc platform-binutils ];
        enableParallelBuilding = true;
        dontFixup = true;
      };

      newlib-pkg = { platform-binutils, platform-gcc }: pkgs.stdenv.mkDerivation rec {
        pname = "newlib";
        version = "3.1.0";
        src = pkgs.fetchurl {
          url = "ftp://sourceware.org/pub/newlib/newlib-${version}.tar.gz";
          sha256 = "0ahh3n079zjp7d9wynggwrnrs27440aac04340chf1p9476a2kzv";
        };
        nativeBuildInputs = [ platform-binutils platform-gcc ];
        configureFlags = [
          "--target=${gnu-platform}"

          "--with-cpu=cortex-a9"
          "--with-fpu=vfpv3"
          "--with-float=hard"
          "--with-mode=thumb"
          "--enable-interwork"
          "--disable-multilib"

          "--disable-newlib-supplied-syscalls"
          "--with-gnu-ld"
          "--with-gnu-as"
          "--disable-newlib-io-float"
          "--disable-werror"
        ];
        dontFixup = true;
      };
      
      gnutoolchain = rec {
        binutils-bootstrap = pkgs.callPackage binutils-pkg { };
        gcc-bootstrap = pkgs.callPackage gcc-pkg {
          platform-binutils = binutils-bootstrap;
          extraConfigureFlags = [ "--disable-libgcc" ];
        };
        newlib = pkgs.callPackage newlib-pkg {
          platform-binutils = binutils-bootstrap;
          platform-gcc = gcc-bootstrap;
        };
        binutils = pkgs.callPackage binutils-pkg {
          extraConfigureFlags = [ "--with-lib-path=${newlib}/arm-none-eabi/lib" ];
        };
        gcc = pkgs.callPackage gcc-pkg {
          platform-binutils = binutils;
          extraConfigureFlags = [ "--enable-newlib" "--with-headers=${newlib}/arm-none-eabi/include" ];
        };
      };

      mkbootimage = pkgs.stdenv.mkDerivation {
        pname = "mkbootimage";
        version = "2.3dev";

        src = pkgs.fetchFromGitHub {
          owner = "antmicro";
          repo = "zynq-mkbootimage";
          rev = "872363ce32c249f8278cf107bc6d3bdeb38d849f";
          sha256 = "sha256-5FPyAhUWZDwHbqmp9J2ZXTmjaXPz+dzrJMolaNwADHs=";
        };

        propagatedBuildInputs = [ pkgs.libelf pkgs.pcre ];
        patchPhase = ''
          substituteInPlace Makefile --replace "git rev-parse --short HEAD" "echo nix"
        '';
        installPhase = ''
          mkdir -p $out/bin
          cp mkbootimage $out/bin
        '';
        # fix crash; see https://github.com/xmrig/xmrig/issues/3305
        hardeningDisable = [ "fortify" ];
      };

      # Pinned qemu version due to networking errors in recent version 8.2.0
      qemu = pkgs.qemu.overrideAttrs (oldAttrs: rec {
        version = "8.1.3";
        src = pkgs.fetchurl {
          url = "https://download.qemu.org/qemu-${version}.tar.xz";
          hash = "sha256-Q8wXaAQQVYb3T5A5jzTp+FeH3/QA07ZA2B93efviZbs=";
        };
      });

      build = { board }: let
        fsbl = pkgs.stdenv.mkDerivation {
          name = "${board}-fsbl";
          src = pkgs.fetchFromGitHub {
            owner = "Xilinx";
            repo = "embeddedsw";
            rev = "xilinx_v2022.2";
            sha256 = "sha256-UDz9KK/Hw3qM1BAeKif30rE8Bi6C2uvuZlvyvtJCMfw=";
          };
          nativeBuildInputs = [
            pkgs.gnumake
            gnutoolchain.binutils
            gnutoolchain.gcc
          ];
          postUnpack = ''
            mkdir -p $sourceRoot/lib/sw_apps/zynq_fsbl/misc/fast-servo
            cp $sourceRoot/lib/sw_apps/zynq_fsbl/misc/zc706/* $sourceRoot/lib/sw_apps/zynq_fsbl/misc/fast-servo
            cp ${fsbl-support}/* $sourceRoot/lib/sw_apps/zynq_fsbl/misc/fast-servo
          '';
          patches = [] ++ pkgs.lib.optional (board == "fast-servo") ./fast-servo/fsbl.patch;
          postPatch = ''
            patchShebangs lib/sw_apps/zynq_fsbl/misc/copy_bsp.sh
            echo 'SEARCH_DIR("${gnutoolchain.newlib}/arm-none-eabi/lib");' >> lib/sw_apps/zynq_fsbl/src/lscript.ld
          '';
          buildPhase = ''
            cd lib/sw_apps/zynq_fsbl/src
            make BOARD=${board} "CFLAGS=-DFSBL_DEBUG_INFO -g"
          '';
          installPhase = ''
            mkdir $out
            cp fsbl.elf $out
          '';
          doCheck = false;
          dontFixup = true;
        };

        u-boot = (pkgs.pkgsCross.armv7l-hf-multiplatform.buildUBoot {
          defconfig = "xilinx_zynq_virt_defconfig";
          patches = [] ++ pkgs.lib.optional (board == "fast-servo") ./fast-servo/u-boot.patch;
          preConfigure = ''
            export DEVICE_TREE=zynq-${board}
          '';
          extraConfig = ''
            CONFIG_SYS_PROMPT="${board}-boot> "
            CONFIG_AUTOBOOT=y
            CONFIG_BOOTCOMMAND="${builtins.replaceStrings [ "\n" ] [ "; " ] ''
              setenv bootargs 'root=/dev/mmcblk0p2 console=ttyPS0,115200n8 systemConfig=${builtins.unsafeDiscardStringContext not-os-cfg.build.toplevel}'
              fatload mmc 0 0x6400000 uImage
              fatload mmc 0 0x8000000 ${board}.dtb
              fatload mmc 0 0xA400000 uRamdisk.image.gz
              bootm 0x6400000 0xA400000 0x8000000
            ''}"
            CONFIG_BOOTDELAY=0
            CONFIG_USE_BOOTCOMMAND=y
          '';
          extraMeta.platforms = [ "armv7l-linux" ];
          filesToInstall = [ "u-boot.elf" ];
        }).overrideAttrs (oldAttrs: {
          postUnpack = ''
            cp ${dts-support}/fast-servo.dts $sourceRoot/arch/arm/dts/zynq-fast-servo.dts
          '';
          postInstall = ''
            mkdir -p $out/dts
            cp arch/arm/dts/zynq-fast-servo.dts $out/dts
            cp arch/arm/dts/zynq-zc706.dts $out/dts
            cp arch/arm/dts/zynq-7000.dtsi $out/dts
          '';
        });

        bootimage = pkgs.runCommand "${board}-bootimage"
          {
            buildInputs = [ mkbootimage ];
          }
          ''
            bifdir=`mktemp -d`
            cd $bifdir
            ln -s ${fsbl}/fsbl.elf fsbl.elf
            ln -s ${u-boot}/u-boot.elf u-boot.elf
            cat > boot.bif << EOF
            the_ROM_image:
            {
              [bootloader]fsbl.elf
              u-boot.elf
            }
            EOF
            mkdir $out $out/nix-support
            mkbootimage boot.bif $out/boot.bin
            echo file binary-dist $out/boot.bin >> $out/nix-support/hydra-build-products
          '';

        dtb = pkgs.runCommand "dtb"
          {
            buildInputs = [ pkgs.gcc pkgs.dtc ];
          }
          ''
            mkdir -p $out
            DTSDIR=$(mktemp -d /tmp/dts-XXXXXX)
            cd $DTSDIR
            cp ${u-boot}/dts/zynq-${board}.dts .

            if [ ${board} == "zc706" ]; then
              mv zynq-${board}.dts zynq-${board}-top.dts
              cp ${u-boot}/dts/zynq-7000.dtsi .
              gcc -E -nostdinc -undef -D__DTS__ -x assembler-with-cpp -o zynq-${board}.dts zynq-${board}-top.dts
            fi

            dtc -I dts -O dtb -o ${board}.dtb zynq-${board}.dts
            cp ${board}.dtb $out
            rm -rf $DTSDIR
          '';

        sd-image = let
          rootfsImage = pkgs.callPackage (pkgs.path + "/nixos/lib/make-ext4-fs.nix") {
            storePaths = [ not-os-cfg.build.toplevel ];
            volumeLabel = "ROOT";
          };
          # Current firmware (kernel, bootimage, etc..) takes ~18MB
          firmwareSize = 30;
          firmwarePartitionOffset = 8;
          in pkgs.stdenv.mkDerivation {
            name = "sd-image";
            nativeBuildInputs = with pkgs; [ dosfstools mtools libfaketime util-linux parted ];
            buildCommand = ''
              mkdir -p $out/nix-support $out/sd-image
              export img=$out/sd-image/sd-image.img

              echo "${pkgs.stdenv.buildPlatform.system}" > $out/nix-support/system
              echo "file sd-image $img" >> $out/nix-support/hydra-build-products

              gap=${toString firmwarePartitionOffset}

              rootSizeBlocks=$(du -B 512 --apparent-size ${rootfsImage} | awk '{ print $1 }')
              firmwareSizeBlocks=$((${toString firmwareSize} * 1024 * 1024 / 512))
              imageSize=$((rootSizeBlocks * 512 + firmwareSizeBlocks * 512 + gap * 1024 * 1024))
              truncate -s $imageSize $img

              fat32Start="$((gap))MB"
              fat32End="$((gap + ${toString firmwareSize}))MB"

              parted $img mklabel msdos
              parted $img mkpart primary fat32 $fat32Start $fat32End
              parted $img mkpart primary ext4 $fat32End 100%
              parted $img set 1 boot on

              eval $(partx $img -o START,SECTORS --nr 2 --pairs)
              dd conv=notrunc if=${rootfsImage} of=$img seek=$START count=$SECTORS

              eval $(partx $img -o START,SECTORS --nr 1 --pairs)
              truncate -s $((SECTORS * 512)) firmware_part.img
              faketime "1970-01-01 00:00:00" mkfs.vfat -n BOOT firmware_part.img

              mkdir firmware
              cp ${bootimage}/boot.bin firmware/
              cp ${dtb}/${board}.dtb firmware/
              cp ${not-os-cfg.build.kernel}/uImage firmware/
              cp ${not-os-cfg.build.uRamdisk}/initrd firmware/uRamdisk.image.gz

              (cd firmware; mcopy -psvm -i ../firmware_part.img ./* ::)
              dd conv=notrunc if=firmware_part.img of=$img seek=$START count=$SECTORS
            '';
          };

        not-os-qemu = let
          qemuScript = ''
            #!/bin/bash
            export PATH=${qemu}/bin:$PATH
            IMGDIR=$(mktemp -d /tmp/not-os-qemu-XXXXXX)
            BASE=$(realpath $(dirname $0))
            qemu-img create -F raw -f qcow2 -b $BASE/sd-image.img $IMGDIR/sd-overlay.qcow2 512M

            # Some command arguments are based from samples in Xilinx QEMU User Documentation
            # See: https://xilinx-wiki.atlassian.net/wiki/spaces/A/pages/821854273/Running+Bare+Metal+Applications+on+QEMU

            qemu-system-arm \
              -M xilinx-zynq-a9 \
              -m 1024 \
              $([ ${board} = "zc706" ] && echo "-serial /dev/null") -serial stdio \
              -display none \
              -kernel $BASE/u-boot.elf \
              -sd $IMGDIR/sd-overlay.qcow2

            rm -rf $IMGDIR
          '';
          in pkgs.runCommand "not-os-qemu" {
            inherit qemuScript;
            passAsFile = [ "qemuScript" ];
            preferLocalBuild = true;
          }
          ''
            mkdir $out
            cd $out
            cp -s ${u-boot}/u-boot.elf .
            cp -s ${sd-image}/sd-image/sd-image.img .
            cp $qemuScriptPath qemu-script
            chmod +x qemu-script
            patchShebangs qemu-script
          '';
      in {
        "${board}-fsbl" = fsbl;
        "${board}-u-boot" = u-boot;
        "${board}-bootimage" = bootimage;
        "${board}-dtb" = dtb;
        "${board}-sd-image" = sd-image;
        "${board}-qemu" = not-os-qemu;
      };
    in rec {
      packages.x86_64-linux = {
        inherit mkbootimage;
      };
      packages.armv7l-linux =
        (build { board = "zc706"; }) //
        (build { board = "fast-servo"; });
    };
}

