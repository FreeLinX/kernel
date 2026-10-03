#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 FreeLinX OS Project.
#
# build-kernel.sh - rebuild bzImage from upstream source with the LLVM toolchain.
#
# SOURCE.md documents the two make invocations.  This script is those two, plus
# an assertion.
#
# kernel.config used to disagree with the kernel that was shipped: it had
#
#     # CONFIG_FB is not set
#     # CONFIG_DRM_SIMPLEDRM is not set
#     # CONFIG_DRM_BOCHS is not set
#
# while bzImage had been built from something else, so a plain rebuild silently
# produced a different kernel from the one in the repository.  That state is
# gone.  bzImage and kernel.config are now the same build, and
#
#     make olddefconfig            # from kernel.config, nothing else
#
# reproduces .config exactly.  kernel.config is the generated .config of the
# build below, not a hand-written approximation of it.
#
# Why that state existed, and why these symbols are the ones to insist on: with
# no framebuffer console the only console driver left is vgacon, the legacy VGA
# text one.  That is enough on a BIOS boot, provided the bootloader hands over a
# text screen rather than a framebuffer.  It is not enough on a UEFI boot at all:
# Limine reports VIDEO_TYPE_EFI there unconditionally, and vgacon's first act is
# to refuse it.
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
# With fbcon present the console does not depend on how the bootloader set up
# video at all: it takes the framebuffer the DRM driver registers and draws into
# that, on BIOS and UEFI alike, and vgacon stays as the fallback for a machine
# with a real VGA card and no other driver.  The symbols enabled below are that
# configuration.  They are already in kernel.config, so each enable() is a no-op
# that re-asserts; they are kept because a config edited from here is exactly
# how the disagreement came about, and a kernel with no framebuffer console in it
# boots to a black screen rather than complaining.
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
# have to agree with what this exact kernel version offers, and a config naming a
# symbol that does not exist is dropped silently.
#
# One such line has already been nearly lost.  An earlier revision of
# kernel.config carried
#
#     # CONFIG_VT_HW_CONSOLE_BINDING is not set
#
# with a note saying it was a 6.9 symbol that meant nothing in 6.6.  It is real
# in 6.6, at drivers/tty/Kconfig:83, `def_bool y` on HW_CONSOLE, and it is =y in
# the config now.  It decides something: it is what lets the VT bind a console
# driver when more than one is available, which is this kernel exactly, with both
# fbcon and vgacon built in.  A comment calling it meaningless is a licence to
# delete it, so it stays.
#
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

# A link-time requirement for the two drivers above, not a nicety.  Both call
# drm_fbdev_generic_setup(), and the function lives in drm_fbdev_generic.o,
# which is built only when this is on:
#
#     drivers/gpu/drm/Makefile
#         drm_kms_helper-$(CONFIG_DRM_FBDEV_EMULATION) += \
#                 drm_fbdev_generic.o \
#                 drm_fb_helper.o
#
# It is also what registers /dev/fb0, which is the framebuffer fbcon binds to,
# so without it there is no console to draw on even with FB and fbcon set.
enable CONFIG_DRM_FBDEV_EMULATION

# The other half of simpledrm on x86, and the kernel says so itself:
#
#     drivers/gpu/drm/tiny/Kconfig, config DRM_SIMPLEDRM
#       On x86 BIOS or UEFI systems, you should also select SYSFB_SIMPLEFB
#       to use UEFI and VESA framebuffers.
#
# simpledrm binds a platform device, and on x86 the one that carries the
# firmware's framebuffer is simplefb's.  Without it, a Limine boot that hands
# over a linear framebuffer on a machine with no PCI display adapter has a
# driver for it nowhere and no console.  Harmless where there is such an
# adapter: there is no simple-framebuffer device to claim.
enable CONFIG_SYSFB_SIMPLEFB

# vgacon stays on.  It is still the right driver for a machine with a real VGA
# card and no KMS driver, and with fbcon also present the two coexist: fbcon takes
# over when a framebuffer is registered and vgacon has the text console otherwise.
printf '\n== the console drivers this kernel will have ==\n'
grep -E '^CONFIG_(FB|FB_CORE|FRAMEBUFFER_CONSOLE|FB_VESA|DRM_SIMPLEDRM|DRM_BOCHS|DRM_FBDEV_EMULATION|SYSFB_SIMPLEFB|VGA_CONSOLE|VT_HW_CONSOLE_BINDING)=' \
	"$TREE/.config" || true

printf '\n== building ==\n'
make -C "$TREE" LLVM=1 LLVM_IAS=1 ARCH=x86_64 CC=clang -j"$(nproc)"

out=$TREE/arch/x86/boot/bzImage
[ -f "$out" ] || die "the build finished but $out is not there"
printf '\n== built ==\n%s\n%s bytes\n' "$out" "$(wc -c <"$out" | tr -d ' ')"