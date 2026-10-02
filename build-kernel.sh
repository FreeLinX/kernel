#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 FreeLinX OS Project.
#
# build-kernel.sh - rebuild bzImage from upstream source with the LLVM toolchain.
#
# SOURCE.md documents the two make invocations.  This script is those two, plus
# the part that is easy to get wrong by hand: the config in this repository is
# not the config the shipped kernel was built from, so a plain rebuild silently
# produces a different kernel.
#
# The differences are in the graphics console, and they are the whole reason this
# script exists.  kernel.config has:
#
#     # CONFIG_FB is not set
#     # CONFIG_DRM_SIMPLEDRM is not set
#     # CONFIG_DRM_BOCHS is not set
#
# so there is no fbcon and no KMS driver for the virtual adapters QEMU hands out,
# and the only console driver left is vgacon - the legacy VGA text one.  That is
# enough on a BIOS boot, provided the bootloader hands over a text screen rather
# than a framebuffer.  It is not enough on a UEFI boot at all: Limine reports
# VIDEO_TYPE_EFI there unconditionally, and vgacon's first act is to refuse it.
#
#     drivers/video/console/vgacon.c:155
#         if (screen_info.orig_video_isVGA == VIDEO_TYPE_VLFB ||
#             screen_info.orig_video_isVGA == VIDEO_TYPE_EFI) {
#           no_vga:
#             conswitchp = &dummy_con;
#
# With no fbcon behind it that leaves the dummy console, which draws nothing, so
# a UEFI machine with no serial cable shows the firmware and then a black screen.
#
# So this script enables the framebuffer console and the driver that provides a
# framebuffer for the QEMU adapters.  With fbcon present the console does not
# depend on how the bootloader set up video at all: it takes the framebuffer the
# DRM driver registers and draws into that, on BIOS and UEFI alike, and vgacon
# stays as the fallback for a machine with a real VGA card and no other driver.
#
# Usage:  sh build-kernel.sh [TREE]      TREE defaults to /tmp/opencode/linux-6.6.21
#
# Writes arch/x86/boot/bzImage in TREE and prints its path.  It does not install
# it into src/rootfs/boot: that is a separate, deliberate step, so that a kernel
# can be built and tested without the shipped image changing underneath it.
set -eu

TREE=${1:-/tmp/opencode/linux-6.6.21}
HERE=$(cd "$(dirname "$0")" && pwd)

[ -f "$TREE/Makefile" ] || die "$TREE does not look like a Linux source tree"
command -v clang >/dev/null || die 'clang is not on PATH'

# olddefconfig is used rather than a hand-written .config because the values here
# have to agree with what this exact kernel version offers: a config naming a
# symbol that does not exist in 6.6 is dropped silently, and this kernel.config
# already carries one, CONFIG_VT_HW_CONSOLE_BINDING, which is a 6.9 symbol.  It
# reads as though it says something about the VT console and says nothing at all.
# 6.6 spells that decision CONFIG_VGA_CONSOLE, which is already =y.
# enable SYMBOL - turn one symbol on and insist that it is on afterwards.
#
# scripts/config, not a written .config: this file is appended to, not replaced,
# and replacing it throws away every other choice made so far - including the
# kernel.config just copied in, which is the point of starting from it.  An
# earlier version wrote the symbol into .config as a bare line:
#
#     .config:1:warning: unexpected data: the framebuffer subsystem
#
# because the value passed was the human description rather than the symbol, and
# the check below then correctly reported that CONFIG_FB was not set.  The check
# did its job; the mistake was in what was written.
#
# The check runs after the config step, not before: a symbol whose dependencies
# are unmet is dropped from the result, so asking for it and not looking leaves a
# kernel that quietly lacks the thing that was asked for.  This is the check that
# would have caught that, and it is why the failure above was a refusal to build
# rather than a kernel with no framebuffer in it.
enable() {
	[ -x "$TREE/scripts/config" ] || die "no scripts/config in $TREE"
	"$TREE/scripts/config" --file "$TREE/.config" --enable "$1"
	make -C "$TREE" LLVM=1 LLVM_IAS=1 ARCH=x86_64 CC=clang olddefconfig >/dev/null
	if ! grep -qx "$1=y" "$TREE/.config"; then
		die "$1 did not survive olddefconfig; the kernel would build without it"
	fi
}

die() { printf 'build-kernel: %s\n' "$1" >&2; exit 1; }

cp "$HERE/kernel.config" "$TREE/.config"
make -C "$TREE" LLVM=1 LLVM_IAS=1 ARCH=x86_64 CC=clang olddefconfig >/dev/null

# Framebuffer console: the fallback that does not care how video was set up.
enable CONFIG_FB
enable CONFIG_FRAMEBUFFER_CONSOLE
enable CONFIG_FRAMEBUFFER_CONSOLE_DETECT_PRIMARY

# The KMS drivers for the adapters QEMU hands out.  simpledrm is the generic one
# and matches anything that registers as a platform device; bochs is named
# because -vga std on QEMU is a Bochs display adapter, and it is the path the
# live-boot test actually exercises.
enable CONFIG_DRM_SIMPLEDRM
enable CONFIG_DRM_BOCHS

# Without this a DRM card registers a /dev/dri node but no /dev/fbN, so Xorg's
# fbdev driver has nothing to open and the desktop service waits forever for a
# display that the kernel is holding back.
enable CONFIG_DRM_FBDEV_EMULATION

# vgacon stays on.  It is still the right driver for a machine with a real VGA
# card and no KMS driver, and with fbcon also present the two coexist: fbcon takes
# over when a framebuffer is registered and vgacon has the text console otherwise.
printf '\n== the console drivers this kernel will have ==\n'
grep -E '^CONFIG_(FB|FB_CORE|FRAMEBUFFER_CONSOLE|FB_VESA|DRM_SIMPLEDRM|DRM_BOCHS|DRM_FBDEV_EMULATION|VGA_CONSOLE|VT_HW_CONSOLE_BINDING)=' \
	"$TREE/.config" || true

printf '\n== building ==\n'
make -C "$TREE" LLVM=1 LLVM_IAS=1 ARCH=x86_64 CC=clang -j"$(nproc)"

out=$TREE/arch/x86/boot/bzImage
[ -f "$out" ] || die "the build finished but $out is not there"
printf '\n== built ==\n%s\n%s bytes\n' "$out" "$(wc -c <"$out" | tr -d ' ')"