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

## Status

The kernel builds successfully with Clang 21.1.8 and no GNU binutils.
It has been tested in QEMU with a FreeLinX BusyBox initramfs and boots
to a working shell. The configuration is defconfig-based and has not yet
been trimmed or hardened for a production build.

See SOURCE.md for build notes and known configuration deviations from
the stock defconfig.

## Related repositories

- toolchain — the LLVM and musl toolchain used to build this kernel
- ports — userland packages built with the same toolchain
- src — root filesystem assembly 
- iso — bootable image packaging
