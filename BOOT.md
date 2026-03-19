# Plain-QEMU Boot Notes

## Scope

This file documents the exact process for taking the already-built
`aosp_cf_arm64_only_phone_qemu` output and turning it into a bootable
plain-QEMU bundle that does not require the cuttlefish harness.

Naming:

- built product: `aosp_cf_arm64_only_phone_qemu`
- staged runtime bundle: `/home/azureuser/aosp/plain-qemu`
- launcher path: `/home/azureuser/aosp/scripts/run_plain_qemu.sh`

Important path detail:

- the scripts currently read compiled images from
  `/home/azureuser/aosp/src/out/target/product/vsoc_arm64_only`
- that directory name is board/output-layout based; it is still the correct
  output directory for the `aosp_cf_arm64_only_phone_qemu` build in this
  workspace

No-harness requirement:

- this flow does not use `launch_cvd`
- this flow does not use `run_cvd`
- the validated path uses host TCP forwarding to guest port `5555`
- the QEMU init fragment stops `socket_vsock_proxy`
- the QEMU init fragment also stops the Wi-Fi helper services and brings `eth0`
  up directly

## Current Validated Status

Validated on `2026-03-19` with the current `plain-qemu/` bundle:

- booted directly in plain QEMU without `launch_cvd` or `run_cvd`
- validated on this no-GPU server with software GL
- `adb` reached `device` on `127.0.0.1:6530`
- `sys.boot_completed=1`
- `/dev/block/by-name/frp` existed and resolved to `/dev/block/vda2`
- runtime graphics properties matched the validated launch overrides:
  - `ro.hardware.egl=angle`
  - `ro.hardware.gralloc=minigbm`
  - `ro.hardware.hwcomposer=ranchu`
  - `ro.hardware.vulkan=ranchu`

Validated command results:

```bash
/home/azureuser/aosp/src/out/host/linux-x86/bin/adb devices -l
# 127.0.0.1:6530 device product:aosp_cf_arm64_only_phone_qemu ...

/home/azureuser/aosp/src/out/host/linux-x86/bin/adb -s 127.0.0.1:6530 get-state
# device

/home/azureuser/aosp/src/out/host/linux-x86/bin/adb -s 127.0.0.1:6530 shell getprop sys.boot_completed
# 1

/home/azureuser/aosp/src/out/host/linux-x86/bin/adb -s 127.0.0.1:6530 shell getprop ro.build.fingerprint
# generic/aosp_cf_arm64_only_phone_qemu/vsoc_arm64_only:Baklava/MAIN/eng.azureu:userdebug/test-keys

/home/azureuser/aosp/src/out/host/linux-x86/bin/adb -s 127.0.0.1:6530 shell ls -l /dev/block/by-name/frp
# /dev/block/by-name/frp -> /dev/block/vda2
```

## Step 1: Prepare The Plain-QEMU Bundle

If you want a clean restage, remove the previous bundle first:

```bash
cd /home/azureuser/aosp
rm -rf plain-qemu
./scripts/prepare_plain_qemu.sh
```

The prep script now carries its own boot-image unpacker at
`scripts/unpack_bootimg.py`, so staging does not depend on the AOSP-host
`unpack_bootimg` binary being present on the machine that prepares the bundle.

The prep script consumes these compiled build outputs:

- `/home/azureuser/aosp/src/out/target/product/vsoc_arm64_only/boot.img`
- `/home/azureuser/aosp/src/out/target/product/vsoc_arm64_only/init_boot.img`
- `/home/azureuser/aosp/src/out/target/product/vsoc_arm64_only/vendor_boot.img`
- `/home/azureuser/aosp/src/out/target/product/vsoc_arm64_only/super.img`
- `/home/azureuser/aosp/src/out/target/product/vsoc_arm64_only/userdata.img`
- `/home/azureuser/aosp/src/out/target/product/vsoc_arm64_only/vbmeta.img`
- `/home/azureuser/aosp/src/out/target/product/vsoc_arm64_only/vbmeta_system.img`
- `/home/azureuser/aosp/src/out/target/product/vsoc_arm64_only/vbmeta_vendor_dlkm.img`
- `/home/azureuser/aosp/src/out/target/product/vsoc_arm64_only/vbmeta_system_dlkm.img`

The prep script does all of the following:

- unpacks `boot.img`, `init_boot.img`, and `vendor_boot.img`
- extracts the kernel, vendor ramdisk, generic ramdisk, DTB, and vendor bootconfig
- converts `super.img` and `userdata.img` from sparse to raw
- creates blank `misc.img` and `frp.img`
- creates a formatted `metadata.img`
- concatenates the vendor and generic ramdisks into `combined_ramdisk.img`
- appends extra bootconfig entries to the vendor bootconfig
- emits `initrd.img`
- assembles a single GPT disk image as `os-disk.raw`

The bootable QEMU bundle is:

- `plain-qemu/kernel`
- `plain-qemu/initrd.img`
- `plain-qemu/os-disk.raw`

Supporting staged artifacts are also kept:

- `plain-qemu/kernel.cmdline`
- `plain-qemu/vendor_ramdisk.lz4`
- `plain-qemu/vendor_bootconfig.txt`
- `plain-qemu/super.raw`
- `plain-qemu/userdata.raw`
- `plain-qemu/misc.img`
- `plain-qemu/frp.img`
- `plain-qemu/metadata.img`

The retained `vendor_ramdisk.lz4` and `vendor_bootconfig.txt` matter because
`scripts/run_plain_qemu.sh` rebuilds `initrd.img` at launch time when you
override `QEMU_BOOT_*` environment variables.

The retained `generic_ramdisk.img` and `combined_ramdisk.img` matter because
Cuttlefish needs the generic ramdisk from `init_boot.img` in addition to the
vendor ramdisk from `vendor_boot.img`; dropping it reproduces the early
recovery-style boot loop.

If the compiled output directory or staging directory differs, override them:

```bash
cd /home/azureuser/aosp
OUT=/path/to/out/target/product/vsoc_arm64_only \
STAGE=/path/to/plain-qemu \
./scripts/prepare_plain_qemu.sh
```

## Step 2: Boot With `ranchu` As The Guest Vulkan Default

`third-party/aosp/` owns the guest-image side of the graphics stack.

Current Phase 2 policy:

- the primary guest Vulkan HAL is `ranchu`
- `pastel` is the legacy SwiftShader-backed fallback
- the intended accelerated host pairing is a gfxstream/rutabaga-capable QEMU
  path
- if the host cannot provide that path yet, software-rendered bring-up is still
  useful for validating the guest image and boot flow

## Step 3: Boot On This No-GPU Server With Software GL

This server does not have a physical GPU. The validated path here uses:

- `xvfb-run` for a temporary X display
- Mesa `llvmpipe` on the host
- guest graphics selection through launch-time `androidboot.hardware.*`
  overrides

Validated launch command:

```bash
cd /home/azureuser/aosp
xvfb-run -a env \
  LIBGL_ALWAYS_SOFTWARE=1 \
  GALLIUM_DRIVER=llvmpipe \
  MESA_LOADER_DRIVER_OVERRIDE=llvmpipe \
  QEMU_DISPLAY=gtk \
  QEMU_GPU_DEVICE='virtio-gpu-pci,id=gpu0,xres=720,yres=1280' \
  QEMU_HOST_ADB_PORT=6530 \
  QEMU_STDIO_HVC=99 \
  QEMU_HVC0_FILE=/tmp/qemu-session-hvc0.log \
  QEMU_HVC2_FILE=/tmp/qemu-session-hvc2.log \
  QEMU_BOOT_HARDWARE_EGL=angle \
  QEMU_BOOT_HARDWARE_GRALLOC=minigbm \
  QEMU_BOOT_HARDWARE_HWCOMPOSER=ranchu \
  QEMU_BOOT_HARDWARE_HWCOMPOSER_MODE=client \
  QEMU_BOOT_HARDWARE_HWCOMPOSER_DISPLAY_FINDER_MODE=drm \
  QEMU_BOOT_HARDWARE_HWCOMPOSER_DISPLAY_FRAMEBUFFER_FORMAT=rgba \
  QEMU_BOOT_HARDWARE_VULKAN=ranchu \
  ./scripts/run_plain_qemu.sh
```

Important details:

- `scripts/run_plain_qemu.sh` defaults `QEMU_DISPLAY` to `none`, so set
  `QEMU_DISPLAY=gtk` for the validated software-GL path
- `QEMU_STDIO_HVC=99` disables stdio-backed virtconsoles, which avoids
  background job-control stops when QEMU is launched from a terminal
- `QEMU_HVC0_FILE` and `QEMU_HVC2_FILE` are the most useful guest log captures
- if `6530` is already in use, pick another free host port and use the same
  value consistently in the `adb` commands below

## Step 4: Wait For ADB And Boot Completion

Use the AOSP-built `adb` binary:

```bash
/home/azureuser/aosp/src/out/host/linux-x86/bin/adb connect 127.0.0.1:6530
/home/azureuser/aosp/src/out/host/linux-x86/bin/adb devices -l
/home/azureuser/aosp/src/out/host/linux-x86/bin/adb -s 127.0.0.1:6530 wait-for-device
/home/azureuser/aosp/src/out/host/linux-x86/bin/adb -s 127.0.0.1:6530 get-state
/home/azureuser/aosp/src/out/host/linux-x86/bin/adb -s 127.0.0.1:6530 shell getprop sys.boot_completed
/home/azureuser/aosp/src/out/host/linux-x86/bin/adb -s 127.0.0.1:6530 shell getprop ro.build.fingerprint
/home/azureuser/aosp/src/out/host/linux-x86/bin/adb -s 127.0.0.1:6530 shell ls -l /dev/block/by-name/frp
```

Expected successful end state:

```text
adb state -> device
sys.boot_completed -> 1
/dev/block/by-name/frp -> /dev/block/vda2
```

Typical progression on this image:

- guest `adbd` starts before the framework is fully settled
- host `adb devices` can briefly show `offline`
- `adb connect` can already return `connected` while the transport is still
  transient
- first boot spends time in APEX decompression and `cppreopts`
- the final target state should become `device`

## Step 5: Useful Post-Boot Checks

Once `adb` is online, these checks are useful:

```bash
/home/azureuser/aosp/src/out/host/linux-x86/bin/adb -s 127.0.0.1:6530 shell getprop ro.hardware.egl
/home/azureuser/aosp/src/out/host/linux-x86/bin/adb -s 127.0.0.1:6530 shell getprop ro.hardware.gralloc
/home/azureuser/aosp/src/out/host/linux-x86/bin/adb -s 127.0.0.1:6530 shell getprop ro.hardware.hwcomposer
/home/azureuser/aosp/src/out/host/linux-x86/bin/adb -s 127.0.0.1:6530 shell getprop ro.hardware.vulkan
/home/azureuser/aosp/src/out/host/linux-x86/bin/adb -s 127.0.0.1:6530 shell ls -l /dev/dri
/home/azureuser/aosp/src/out/host/linux-x86/bin/adb -s 127.0.0.1:6530 shell readlink -f /sys/class/drm/card0/device/driver
```

On the validated run, the graphics properties were:

```text
ro.hardware.egl=angle
ro.hardware.gralloc=minigbm
ro.hardware.hwcomposer=ranchu
ro.hardware.vulkan=ranchu
```

## Known Blockers Already Fixed

### 1. Missing `frp` GPT partition

The earlier raw-disk bundle was missing an `frp` partition even though the
product exposes:

```text
ro.frp.pst=/dev/block/by-name/frp
```

Without that partition, `PersistentDataBlockService` timed out during boot and
`system_server` died. The fix lives in `scripts/prepare_plain_qemu.sh`, which
now creates and assembles:

- `misc.img`
- `frp.img`
- `metadata.img`

### 2. Stale experimental QEMU audio-policy leftovers

Earlier experimental work added QEMU-specific audio-policy files, but those are
not part of the current validated tree.

Current status:

- the stale QEMU audio-policy leftovers were removed
- the current validated build does not rely on a custom QEMU audio-policy
  module
- the validated image boots and reaches `adb device` without those leftovers

## Known Non-Blocking Runtime Issues

The current validated boot still shows a few guest-side runtime problems that
do not block `adb` or `sys.boot_completed=1`.

Observed on `2026-03-19`:

- `com.android.nfc` aborts and restarts after NFC HAL command timeouts
  - `libnfc_nci_jni.so`
  - `nfc_ncif_cmd_timeout`
  - `NFA_DM_NFCC_TIMEOUT_EVT`
- `com.android.bluetooth` also aborts and restarts later in boot
  - native crash in `bt_stack_manager_thread`
- `audioserver` repeatedly tries to start lazy `aidl/activity`

These issues are visible in `/tmp/qemu-session-hvc2.log`, but they did not
prevent:

- `adb device`
- `sys.boot_completed=1`
- interactive shell access through ADB

## If Boot Stalls, Inspect The Right Logs

Primary guest logs:

- `/tmp/qemu-session-hvc0.log`
- `/tmp/qemu-session-hvc2.log`

Useful host-side grep examples:

```bash
grep -nE 'PersistentDataBlockService|audio_policy_configuration|IModule/default|eglInitialize|FATAL' /tmp/qemu-session-hvc2.log
grep -nE 'virtio_gpu|drm|SurfaceFlinger|audioserver|adbd|com.android.nfc|droid.bluetooth' /tmp/qemu-session-hvc0.log /tmp/qemu-session-hvc2.log
```

High-signal failure patterns:

- `PersistentDataBlockService` errors mentioning `frp`
  - usually means the staged disk was not rebuilt with the current prep script
- repeated `SurfaceFlinger` aborts around `eglInitialize()`
  - graphics bring-up is failing
- `adb` remains `offline` for a long time during first boot
  - wait for APEX decompression and `cppreopts` to finish before deciding it is
    stuck
- repeated `com.android.nfc` or `com.android.bluetooth` crashes
  - currently non-blocking, but still worth tracking

## Running The Same Bundle On Another Machine With Virgl Or Gfxstream

Do not rebuild just to switch host graphics backend. The bundle under
`plain-qemu/` is meant to stay the same.

For a virgl-capable host, the minimal change is usually:

```bash
export QEMU_DISPLAY=gtk
export QEMU_GPU_DEVICE='virtio-gpu-gl-pci,id=gpu0,xres=720,yres=1280'
export QEMU_BOOT_HARDWARE_EGL=mesa
./scripts/run_plain_qemu.sh
```

If the host prefers a headless EGL display backend, swap only the display mode:

```bash
export QEMU_DISPLAY=egl-headless
export QEMU_GPU_DEVICE='virtio-gpu-gl-pci,id=gpu0,xres=720,yres=1280'
export QEMU_BOOT_HARDWARE_EGL=mesa
./scripts/run_plain_qemu.sh
```

For gfxstream-capable QEMU builds, keep the same staged image and change only:

- `QEMU_DISPLAY`
- `QEMU_GPU_DEVICE`
- any required `QEMU_BOOT_HARDWARE_*` overrides for that host

Check the target host first:

```bash
qemu-system-aarch64 -device help | grep -E 'virtio-gpu|gfxstream'
qemu-system-aarch64 -display help
```

## Files Involved

- build output: `/home/azureuser/aosp/src/out/target/product/vsoc_arm64_only`
- prep script: `/home/azureuser/aosp/scripts/prepare_plain_qemu.sh`
- launch script: `/home/azureuser/aosp/scripts/run_plain_qemu.sh`
- staged bundle: `/home/azureuser/aosp/plain-qemu`
