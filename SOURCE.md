# FreeLinix Kernel

Tracks upstream Linux 6.6.21 (LTS), unmodified source.
Upstream: https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.6.21.tar.xz

## Build (no GNU — LLVM toolchain only)

export PATH=~/freelinix/toolchain/bin:\$PATH
tar xf linux-6.6.21.tar.xz
cd linux-6.6.21
cp ../kernel.config .config
make LLVM=1 LLVM_IAS=1 ARCH=x86_64 CC=clang olddefconfig
make LLVM=1 LLVM_IAS=1 ARCH=x86_64 CC=clang -j\$(nproc)

Produces arch/x86/boot/bzImage.

## Deviations from stock defconfig
- CONFIG_WERROR disabled - works around a Clang-21 vs Linux-6.6 -Wenum-enum-conversion
  false-positive in vmstat.h.

## Verified
- Builds clean with clang version 21.1.8 via LLVM=1/LLVM_IAS=1 - zero GNU binutils used.
- Boots successfully in QEMU with a FreeLinix BusyBox initramfs to a working shell.
- /proc/version on the running kernel confirms the Clang toolchain used for the build.
