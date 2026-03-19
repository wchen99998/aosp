# Plain-QEMU Boot Notes

## Scope

This file documents the exact process for taking the already-built
`aosp_cf_arm64_only_phone_qemu` output and turning it into a bootable
plain-QEMU bundle that does not require the cuttlefish harness.

Naming:

- built product: `aosp_cf_arm64_only_phone_qemu`
- staged runtime bundle: `/home/azureuser/aosp/plain-qemu`
- launcher path: `scripts/run_plain_qemu.sh`

`plain-qemu` is the no-harness runtime flow, not a separate build flavor.

Important path detail:

- the scripts currently read compiled images from
  `/home/azureuser/aosp/src/out/target/product/vsoc_arm64_only`
- that directory name is board/output-layout based; it is still the correct
  output directory for the `aosp_cf_arm64_only_phone_qemu` build in this
  workspace

## Current Validated Result

Validated on this no-GPU server on 2026-03-19:

- booted in plain QEMU without `launch_cvd` or `run_cvd`
- `sys.boot_completed=1`
- ADB transport reached `device`
- ADB shell worked
- `/dev/block/by-name/frp` existed and resolved to `/dev/block/vda2`

Validated host-side command results:

```bash
/home/azureuser/aosp/src/out/host/linux-x86/bin/adb -s 127.0.0.1:6522 get-state
# device

/home/azureuser/aosp/src/out/host/linux-x86/bin/adb -s 127.0.0.1:6522 shell getprop sys.boot_completed
# 1

/home/azureuser/aosp/src/out/host/linux-x86/bin/adb -s 127.0.0.1:6522 shell ls -l /dev/block/by-name/frp
# /dev/block/by-name/frp -> /dev/block/vda2
```

## Why The Earlier Boot Failed

The earlier raw-disk bundle was missing an `frp` GPT partition.

That mattered because the product still exposes:

```text
ro.frp.pst=/dev/block/by-name/frp
```

Without that partition, `PersistentDataBlockService` timed out during boot
phase 500 and killed `system_server`.

The fix was not another image rebuild. The fix was to make
`scripts/prepare_plain_qemu.sh` create and include:

- `misc.img`
- `frp.img`
- `metadata.img`

and assemble `frp` into `os-disk.raw`.

## Step 1: Prepare The Plain-QEMU Bundle

Run:

```bash
cd /home/azureuser/aosp
./scripts/prepare_plain_qemu.sh
```

This stages:

- `/home/azureuser/aosp/plain-qemu/kernel`
- `/home/azureuser/aosp/plain-qemu/initrd.img`
- `/home/azureuser/aosp/plain-qemu/os-disk.raw`
- `/home/azureuser/aosp/plain-qemu/kernel.cmdline`
- `/home/azureuser/aosp/plain-qemu/super.raw`
- `/home/azureuser/aosp/plain-qemu/userdata.raw`

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

- unpacks `boot.img` and `vendor_boot.img`
- extracts the kernel, vendor ramdisk, DTB, and bootconfig
- converts `super.img` and `userdata.img` from sparse to raw
- creates blank `misc.img` and `frp.img`
- creates `metadata.img`
- appends bootconfig onto the vendor ramdisk to build `initrd.img`
- assembles a single GPT disk `os-disk.raw`

The actual bootable QEMU artifact is this bundle:

- `plain-qemu/kernel`
- `plain-qemu/initrd.img`
- `plain-qemu/os-disk.raw`

`super.raw` and `userdata.raw` are staged intermediate/supporting artifacts,
not the files that QEMU boots directly.

Current GPT partitions in `os-disk.raw`:

- `misc`
- `frp`
- `boot_a`
- `boot_b`
- `init_boot_a`
- `init_boot_b`
- `vendor_boot_a`
- `vendor_boot_b`
- `vbmeta*`
- `super`
- `userdata`
- `metadata`

If the compiled output directory is somewhere else, the prep script can be
pointed at it explicitly:

```bash
cd /home/azureuser/aosp
OUT=/path/to/out/target/product/vsoc_arm64_only ./scripts/prepare_plain_qemu.sh
```

## Step 2: Boot On This No-GPU Server

This server does not have a physical GPU. The validated path here is:

- Xvfb for a display server
- Mesa llvmpipe on the host
- guest software graphics selection via launch-time `androidboot.hardware.*`

Start Xvfb:

```bash
Xvfb :101 -screen 0 1280x1024x24 >/tmp/xvfb-101.log 2>&1 &
```

Launch QEMU:

```bash
cd /home/azureuser/aosp
DISPLAY=:101 \
GDK_BACKEND=x11 \
LIBGL_ALWAYS_SOFTWARE=1 \
GALLIUM_DRIVER=llvmpipe \
MESA_LOADER_DRIVER_OVERRIDE=llvmpipe \
QEMU_DISPLAY=gtk \
QEMU_STDIO_HVC=99 \
QEMU_HOST_ADB_PORT=6522 \
QEMU_HVC0_FILE=/tmp/qemu-swgl-hvc0.log \
QEMU_HVC2_FILE=/tmp/qemu-swgl-hvc2.log \
./scripts/run_plain_qemu.sh
```

Important details:

- `QEMU_STDIO_HVC=99` disables stdio-backed virtconsoles, which avoids
  background job-control stops when QEMU is daemonized or run under a terminal
- this host's QEMU build did not support `gtk,gl=on`; plain `gtk` worked
- `QEMU_HVC0_FILE` and `QEMU_HVC2_FILE` are the useful guest log captures

The guest-side software-rendered launch selection used by this validated run
was:

- `QEMU_BOOT_HARDWARE_EGL=angle`
- `QEMU_BOOT_HARDWARE_GRALLOC=minigbm`
- `QEMU_BOOT_HARDWARE_HWCOMPOSER=ranchu`
- `QEMU_BOOT_HARDWARE_VULKAN=pastel`

Those values are already the current launcher defaults, so the command above
did not need to override them explicitly.

## Step 3: Wait For Boot Completion

On the host:

```bash
/home/azureuser/aosp/src/out/host/linux-x86/bin/adb connect 127.0.0.1:6522
/home/azureuser/aosp/src/out/host/linux-x86/bin/adb -s 127.0.0.1:6522 wait-for-device
/home/azureuser/aosp/src/out/host/linux-x86/bin/adb -s 127.0.0.1:6522 shell getprop sys.boot_completed
```

Expected final value:

```text
1
```

Typical progression seen on this machine:

- guest `adbd` starts first
- host ADB may briefly show `offline`
- after framework boot finishes, the host transport becomes `device`

## Step 4: Confirm ADB Works

Useful validation commands:

```bash
/home/azureuser/aosp/src/out/host/linux-x86/bin/adb -s 127.0.0.1:6522 get-state
/home/azureuser/aosp/src/out/host/linux-x86/bin/adb -s 127.0.0.1:6522 shell getprop ro.build.fingerprint
/home/azureuser/aosp/src/out/host/linux-x86/bin/adb -s 127.0.0.1:6522 shell getprop ro.hardware.egl
/home/azureuser/aosp/src/out/host/linux-x86/bin/adb -s 127.0.0.1:6522 shell ls -l /dev/block/by-name/frp
```

Validated outputs from this run:

```text
get-state -> device
ro.hardware.egl -> angle
sys.boot_completed -> 1
/dev/block/by-name/frp -> /dev/block/vda2
```

## Running On Another Machine With Virgl Or Gfxstream

The same built image is intentionally launch-selectable. Do not rebuild just
to switch the host graphics backend.

For a virgl-capable host, the usual direction is:

```bash
export QEMU_DISPLAY=egl-headless
export QEMU_GPU_DEVICE='virtio-gpu-gl-pci,id=gpu0,xres=720,yres=1280'
export QEMU_BOOT_HARDWARE_EGL=mesa
```

If the target host prefers a windowed backend:

```bash
export QEMU_DISPLAY=gtk
export QEMU_GPU_DEVICE='virtio-gpu-gl-pci,id=gpu0,xres=720,yres=1280'
export QEMU_BOOT_HARDWARE_EGL=mesa
```

For gfxstream-capable host builds of QEMU, keep the same staged image and swap
only the launch-time GPU device / display selection to the gfxstream device
that the target host QEMU actually exposes.

Check that host first:

```bash
qemu-system-aarch64 -device help | grep -E 'virtio-gpu|gfxstream'
qemu-system-aarch64 -display help
```

The key policy is:

- same image
- same `kernel`, `initrd.img`, and `os-disk.raw`
- different host QEMU GPU device and `androidboot.hardware.*` selection at
  launch time

## Current Caveats

- the source still attempts to set some vendor properties such as
  `persist.adb.tcp.port=5555` from `vendor/build.prop`
- this produces SELinux property-context denials in the guest log
- those denials did not block the validated boot on this artifact

- the current source pruning is focused on bootability without the cuttlefish
  harness
- it already disables the light HAL and Thread network for this QEMU product
- it also stops `socket_vsock_proxy`, `setup_wifi`, and `init_wifi_sh`
- it does not try to remove every inherited cuttlefish package from the image

## Files Involved

- build output: `/home/azureuser/aosp/src/out/target/product/vsoc_arm64_only`
- prep script: `/home/azureuser/aosp/scripts/prepare_plain_qemu.sh`
- launch script: `/home/azureuser/aosp/scripts/run_plain_qemu.sh`
- staged bundle: `/home/azureuser/aosp/plain-qemu`
