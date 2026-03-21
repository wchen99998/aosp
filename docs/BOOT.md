# Plain-QEMU Boot Flow

## Scope

This documents the boot path for the staged `plain-qemu/` bundle produced by
`scripts/prepare_plain_qemu.sh`.

The key paths are:

- staged runtime bundle: `/home/azureuser/aosp/plain-qemu`
- launcher: `/home/azureuser/aosp/scripts/run_plain_qemu.sh`
- AOSP build output: `/home/azureuser/aosp/src/out/target/product/vsoc_arm64_only`

This flow does not use `launch_cvd` or `run_cvd`.

## Current Validation

The latest verified path on this workspace booted a bundle extracted from
`release-assets/` directly in plain QEMU and reached `sys.boot_completed=1` on
`127.0.0.1:6550`.

Validated setup on this host:

- date: `2026-03-20`
- host display: `xvfb-run`
- host GL: Mesa `llvmpipe`
- guest graphics launch: `QEMU_DISPLAY=gtk`
- stdio console: `QEMU_STDIO_HVC=99`
- host ADB port: `6550`

Observed properties on the validated run:

- `adb` connected on `127.0.0.1:6550`
- `debug.hwui.renderer=skiagl`
- `debug.renderengine.backend=skiaglthreaded`
- `ro.surface_flinger.game_default_frame_rate_override=0`
- `debug.graphics.game_default_frame_rate.disabled=true`
- `ro.hardware.egl=angle`
- `ro.hardware.gralloc=minigbm`
- `ro.hardware.hwcomposer=ranchu`
- `ro.hardware.vulkan=pastel`
- `ro.boot.vendor.apex.com.android.hardware.graphics.composer=com.android.hardware.graphics.composer.ranchu`

The same bundle can also be staged from a release archive under
`release-assets/` and then booted with the same launcher.

For this host, the launcher also mirrors critical early-boot args, including
`androidboot.force_normal_boot`, onto the kernel cmdline because bootconfig-only
delivery was not reliable enough for bundle boot verification.

## Prepare The Bundle

If you want to restage from a fresh build:

```bash
cd /home/azureuser/aosp
rm -rf plain-qemu
./scripts/prepare_plain_qemu.sh
```

The staging script unpacks the boot images, extracts the kernel and ramdisks,
converts the sparse images, assembles `os-disk.raw`, and writes the bootconfig
overlay used by the launcher.

## Boot A Bundle From `release-assets`

If you only have a release archive, extract it first, then restage the plain
QEMU bundle from the extracted output:

```bash
cd /home/azureuser/aosp
mkdir -p tmp/release-extract
tar --zstd -xf release-assets/<product>-out-<date>.tar.zst -C tmp/release-extract
OUT=/home/azureuser/aosp/tmp/release-extract \
  STAGE=/home/azureuser/aosp/plain-qemu \
  ./scripts/prepare_plain_qemu.sh
```

After that, boot `plain-qemu/` with `scripts/run_plain_qemu.sh` exactly as you
would after a local build.

## Boot On This Host

This workspace validated the no-GPU path with software GL:

```bash
cd /home/azureuser/aosp
xvfb-run -a env \
  LIBGL_ALWAYS_SOFTWARE=1 \
  GALLIUM_DRIVER=llvmpipe \
  MESA_LOADER_DRIVER_OVERRIDE=llvmpipe \
  QEMU_DISPLAY=gtk \
  QEMU_GPU_DEVICE='virtio-gpu-pci,id=gpu0,xres=720,yres=1280' \
  QEMU_HOST_ADB_PORT=6550 \
  QEMU_STDIO_HVC=99 \
  QEMU_HVC0_FILE=/tmp/qemu-session-hvc0.log \
  QEMU_HVC2_FILE=/tmp/qemu-session-hvc2.log \
  QEMU_BOOT_HARDWARE_EGL=angle \
  QEMU_BOOT_HARDWARE_GRALLOC=minigbm \
  QEMU_BOOT_HARDWARE_HWCOMPOSER=ranchu \
  QEMU_BOOT_HARDWARE_HWCOMPOSER_MODE=client \
  QEMU_BOOT_HARDWARE_HWCOMPOSER_DISPLAY_FINDER_MODE=drm \
  QEMU_BOOT_HARDWARE_HWCOMPOSER_DISPLAY_FRAMEBUFFER_FORMAT=rgba \
  QEMU_BOOT_HARDWARE_VULKAN=pastel \
  QEMU_BOOT_HARDWARE_GUEST_HWUI_RENDERER=skiagl \
  QEMU_BOOT_HARDWARE_GUEST_DISABLE_RENDERER_PRELOAD=false \
  QEMU_BOOT_DEBUG_RENDERENGINE_BACKEND=skiaglthreaded \
  ./scripts/run_plain_qemu.sh
```

Important details:

- set `QEMU_DISPLAY=gtk` for the validated software-GL path
- use `QEMU_STDIO_HVC=99` to avoid stdio-backed virtconsole job-control issues
- capture logs with `QEMU_HVC0_FILE` and `QEMU_HVC2_FILE`
- the launcher mirrors critical early-boot args onto the kernel cmdline, so
  `force_normal_boot` and the graphics boot contract are visible even if
  bootconfig delivery is incomplete on this host
- if `6550` is busy, pick another port and use it consistently in the ADB
  commands below

If you are restaging from a build archive, the same launch flow applies after
`prepare_plain_qemu.sh` has rebuilt `plain-qemu/` from the extracted output.

## Validate Boot Properties

After boot, confirm the graphics contract landed before SurfaceFlinger starts:

```bash
/home/azureuser/aosp/src/out/host/linux-x86/bin/adb -s 127.0.0.1:6550 shell getprop ro.boot.hardware.guest_hwui_renderer
/home/azureuser/aosp/src/out/host/linux-x86/bin/adb -s 127.0.0.1:6550 shell getprop ro.boot.hardware.guest_disable_renderer_preload
/home/azureuser/aosp/src/out/host/linux-x86/bin/adb -s 127.0.0.1:6550 shell getprop ro.boot.debug.renderengine.backend
/home/azureuser/aosp/src/out/host/linux-x86/bin/adb -s 127.0.0.1:6550 shell getprop debug.hwui.renderer
/home/azureuser/aosp/src/out/host/linux-x86/bin/adb -s 127.0.0.1:6550 shell getprop debug.renderengine.backend
/home/azureuser/aosp/src/out/host/linux-x86/bin/adb -s 127.0.0.1:6550 shell getprop ro.zygote.disable_gl_preload
/home/azureuser/aosp/src/out/host/linux-x86/bin/adb -s 127.0.0.1:6550 shell getprop ro.hardware.hwcomposer
/home/azureuser/aosp/src/out/host/linux-x86/bin/adb -s 127.0.0.1:6550 shell getprop ro.boot.vendor.apex.com.android.hardware.graphics.composer
/home/azureuser/aosp/src/out/host/linux-x86/bin/adb -s 127.0.0.1:6550 shell cmd overlay lookup android android:integer/config_defaultPeakRefreshRate
/home/azureuser/aosp/src/out/host/linux-x86/bin/adb -s 127.0.0.1:6550 shell cmd overlay lookup android android:integer/config_defaultRefreshRate
/home/azureuser/aosp/src/out/host/linux-x86/bin/adb -s 127.0.0.1:6550 shell dumpsys display | grep -E 'renderFrameRate|supportedRefreshRates'
```

Expected checks:

- `ro.boot.hardware.guest_hwui_renderer` and
  `ro.boot.hardware.guest_disable_renderer_preload` are present when the boot
  contract is enabled.
- `debug.hwui.renderer` and `debug.renderengine.backend` are populated before
  `surfaceflinger` starts.
- `ro.surface_flinger.game_default_frame_rate_override=0` and
  `debug.graphics.game_default_frame_rate.disabled=true` express the product
  policy on this branch.
- `ro.zygote.disable_gl_preload` reflects the renderer-preload setting.
- `ro.boot.vendor.apex.com.android.hardware.graphics.composer` matches the
  composer backend the launcher selected.
- `ro.hardware.hwcomposer` matches the intended product/backend choice.
- the QEMU guest overlay resolves both `config_defaultPeakRefreshRate` and
  `config_defaultRefreshRate` to `120`.
- on the currently validated plain-QEMU/ranchu path, `dumpsys display` still
  reports `renderFrameRate 75.0` and supported refresh rates that include
  `75.0`, `37.5`, and `25.0`.
- treat the remaining 75 Hz runtime cap as a host/display-mode issue, not a
  guest overlay issue.

## Check Boot Completion

Use the AOSP-built `adb` binary:

```bash
/home/azureuser/aosp/src/out/host/linux-x86/bin/adb connect 127.0.0.1:6550
/home/azureuser/aosp/src/out/host/linux-x86/bin/adb devices -l
/home/azureuser/aosp/src/out/host/linux-x86/bin/adb -s 127.0.0.1:6550 wait-for-device
/home/azureuser/aosp/src/out/host/linux-x86/bin/adb -s 127.0.0.1:6550 get-state
/home/azureuser/aosp/src/out/host/linux-x86/bin/adb -s 127.0.0.1:6550 shell getprop sys.boot_completed
/home/azureuser/aosp/src/out/host/linux-x86/bin/adb -s 127.0.0.1:6550 shell getprop ro.build.fingerprint
/home/azureuser/aosp/src/out/host/linux-x86/bin/adb -s 127.0.0.1:6550 shell ls -l /dev/block/by-name/frp
```

Expected end state:

- `adb state` is `device`
- `sys.boot_completed` is `1`
- `/dev/block/by-name/frp` resolves to `/dev/block/vda2`

## If Boot Looks Wrong

- Do not restart SurfaceFlinger to compensate for a missing boot property.
- Fix the bootconfig, product property, or composer packaging instead.
- Keep physical DPI coming from the display path and UI density from
  `androidboot.lcd_density`.
