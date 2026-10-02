# FreeLinX Kernel

Tracks upstream Linux 6.6.21 (LTS), unmodified source.
Upstream: https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.6.21.tar.xz

## Build (no GNU — LLVM toolchain only)

export PATH=~/freelinix/toolchain/bin:\$PATH
tar xf linux-6.6.21.tar.xz
sh ../build-kernel.sh /path/to/linux-6.6.21

`build-kernel.sh` is the two make lines below plus the part that is easy to get
wrong by hand: the config in this repository is **not** the config the shipped
kernel was built from, so a plain rebuild silently produces a different kernel.

```
make LLVM=1 LLVM_IAS=1 ARCH=x86_64 CC=clang olddefconfig
make LLVM=1 LLVM_IAS=1 ARCH=x86_64 CC=clang -j\$(nproc)
```

It enables the framebuffer console and the KMS drivers QEMU hands out, and then
insists each one survived `olddefconfig`. Produces `arch/x86/boot/bzImage`.

### Why the framebuffer console

The kernel.config this repository carried had `CONFIG_FB` off, no `fbcon`, and
no KMS driver, which left vgacon as the only console driver in the kernel. vgacon
is the legacy VGA text driver and it refuses to bind when the bootloader reports a
framebuffer instead of a text screen:

```c
/* drivers/video/console/vgacon.c */
if (screen_info.orig_video_isVGA == VIDEO_TYPE_VLFB ||
    screen_info.orig_video_isVGA == VIDEO_TYPE_EFI) {
no_vga:
        conswitchp = &dummy_con;
        return conswitchp->con_startup();
}
```

On BIOS, Limine will hand over a text screen when its config asks for one — and
the key is **`textmode`**, with no underscore, which is the subject of its own
comment in `base/build-base.sh`. On UEFI it cannot: Limine reports
`VIDEO_TYPE_EFI` there unconditionally, and the block that would honour the
setting is inside `#if defined(BIOS)`.

So on UEFI the only way to a console is fbcon, which does not care how the
bootloader set up video at all: it takes the framebuffer a DRM driver registers
and draws into that. That is what this config enables. The trade is that with
fbcon present it takes the console from vgacon as soon as a DRM driver
registers —

```
bochs-drm 0000:00:02.0: vgaarb: deactivate vga console
```

— so after boot the console is on the framebuffer and `0xb8000` is stale. A test
that reads `0xb8000` on such a system finds a dead console on a machine that
works; `base/live-boot-vga.py` asks the guest which display is bound and reads
that one instead.

## Deviations from stock defconfig
- CONFIG_WERROR disabled - works around a Clang vs Linux-6.6 -Wenum-enum-conversion
  false-positive in vmstat.h.
- CONFIG_FB, CONFIG_FRAMEBUFFER_CONSOLE, CONFIG_DRM_SIMPLEDRM, CONFIG_DRM_BOCHS,
  CONFIG_DRM_FBDEV_EMULATION enabled - see "Why the framebuffer console" above.
  This is the only deviation that changes what a booted system can do rather
  than how it is compiled.

## A symbol that does not exist in this kernel

`kernel.config` carried `CONFIG_VT_HW_CONSOLE_BINDING`. That is a Linux 6.9
symbol; 6.6 spells the same decision `CONFIG_VGA_CONSOLE`, which was already
`=y`. kconfig drops a symbol it does not recognise without a word, so the line
reads as though it says something about the VT console and says nothing at all.

It is left in place rather than deleted, because `olddefconfig` ignores it safely
and because deleting it would hide that this file was once fed to a newer kernel
than the one it names. `build-kernel.sh` verifies the symbols it cares about by
name after `olddefconfig` rather than trusting the file, which is what makes that
class of thing survivable.

## Verified
- Builds clean with clang via LLVM=1/LLVM_IAS=1 - zero GNU binutils used.
- Boots successfully in QEMU with a FreeLinX BusyBox initramfs to a working shell.
- /proc/version on the running kernel confirms the Clang toolchain used for the build.
- With this config, on QEMU with `-vga std`: `vtcon0` is bound to the framebuffer
  device, `/dev/fb0` and `/dev/dri/card0` both exist, and the serial console and
  the graphical console are both live. Verified by `base/test-live-boot.sh`.
