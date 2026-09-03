# FreeLinX Kernel

This repository contains the kernel configuration and build documentation
for FreeLinX, a Linux distribution built without any GNU components,
using the LLVM toolchain and musl libc.

## Overview

FreeLinX tracks unmodified upstream Linux 6.6.21 (LTS). No kernel patches
or distro-specific source changes are applied. This repository holds the
FreeLinX build configuration and documentation, not the kernel source
itself.

- Upstream source: https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.6.21.tar.xz
- Working configuration: kernel.config
- Build notes: SOURCE.md

## Toolchain

The kernel is built entirely with LLVM=1 and LLVM_IAS=1, using Clang,
ld.lld, and LLVM's integrated assembler. No GCC or GNU binutils are used
at any point in the build. This has been verified by inspecting the build
log for tool invocations, and confirmed at runtime through /proc/version
on a booted system, which reports the Clang version used for the build.

## Build instructions

    export PATH=~/freelinix/toolchain/bin:$PATH

    wget https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.6.21.tar.xz
    tar xf linux-6.6.21.tar.xz
    cd linux-6.6.21
    cp ../kernel.config .config

    make LLVM=1 LLVM_IAS=1 ARCH=x86_64 CC=clang olddefconfig
    make LLVM=1 LLVM_IAS=1 ARCH=x86_64 CC=clang -j$(nproc)

This produces arch/x86/boot/bzImage.

## WiFi support

The configuration ships with loadable `802.11` WiFi driver modules (built
with `make ARCH=x86_64 LLVM=1 modules`, installed stripped with
`INSTALL_MOD_STRIP=1`). These target common Intel, Atheros/Qualcomm and
Broadcom NICs:

| Module            | Chipset                                      | Config                 |
|-------------------|----------------------------------------------|------------------------|
| `iwlwifi`         | Intel Wireless (iwlwifi family)              | `CONFIG_IWLWIFI=m`     |
| `ath9k`           | Atheros 802.11n (PCI / AHB)                  | `CONFIG_ATH9K=m`       |
| `ath9k_htc`       | Atheros USB (AR9271, `htc_7010`/`htc_9271`)  | `CONFIG_ATH9K_HTC=m`   |
| `ath10k_pci`      | Qualcomm/Atheros 802.11ac PCIe (QCA6174 etc.)| `CONFIG_ATH10K_PCI=m`  |
| `brcmfmac`        | Broadcom fullmac (cyw / wcc / bca variants)  | `CONFIG_BRCMFMAC=m`    |
| `brcmsmac`        | Broadcom softmac                             | `CONFIG_BRCMSMAC=m`    |

The `802.11` stack (`cfg80211` + `mac80211`) is built in, and the `device
coredump` support newer WiFi drivers depend on is enabled:

    CONFIG_CFG80211=y
    CONFIG_MAC80211=y
    CONFIG_WANT_DEV_COREDUMP=y
    CONFIG_ALLOW_DEV_COREDUMP=y
    CONFIG_DEV_COREDUMP=y

Build and install the modules into the FreeLinX rootfs:

    make ARCH=x86_64 LLVM=1 modules
    make ARCH=x86_64 LLVM=1 INSTALL_MOD_STRIP=1 modules_install \
         INSTALL_MOD_PATH=../src/rootfs

The following modules are produced and installed (16 `.ko` total):

- `iwlwifi.ko`
- `ath9k.ko`, `ath9k_common.ko`, `ath9k_hw.ko`, `ath9k_htc.ko`
- `ath.ko`, `ath10k_core.ko`, `ath10k_pci.ko`
- `brcmfmac.ko` (+ `brcmfmac-cyw.ko`, `brcmfmac-wcc.ko`, `brcmfmac-bca.ko`)
- `brcmsmac.ko`
- `brcmutil.ko`
- `bcma.ko`, `cordic.ko`

Firmware lives in `src/rootfs/lib/firmware` (see `ports/firmware/linux-firmware`).
Without it a NIC loads its driver but cannot initialize its radio. After
booting with matching firmware, associate (see `ports/README.md` for `flx-wifi`):

    modprobe iwlwifi          # or ath9k / ath10k_pci / brcmfmac
    flx-ifconfig wlan0 up
    flx-wifi scan
    flx-wifi connect "MyNetwork" "password"
    dhcpcd wlan0

## Status

The kernel builds successfully with Clang 21.1.8 and no GNU binutils.
It has been tested in QEMU with a FreeLinX initramfs and boots to a working
root shell. The WiFi modules are verified loading as live drivers in the
booted system (`lsmod` shows the full `ath`/`ath10k`/`brcm` dependency
chains). Real 802.11 association must be tested on physical hardware.

The configuration is defconfig-based and has not yet been trimmed or
hardened for a production build. `MAC80211_HWSIM` is intentionally left
off, so wireless cannot be exercised inside QEMU (no virtual WiFi NIC).

See SOURCE.md for build notes and known configuration deviations from
the stock defconfig.

## Related repositories

- toolchain — the LLVM and musl toolchain used to build this kernel
- ports — userland packages (incl. `flx-wifi`/`wpa_supplicant`) built with the same toolchain
- src — root filesystem assembly (kernel modules + firmware installed here)
- iso — bootable image packaging
