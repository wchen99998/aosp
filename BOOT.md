# Plain-QEMU Boot Notes

## Scope

This file documents the exact split between:

- preparing the built artifacts on the build machine
- launching the prepared artifacts on a separate GPU-capable runtime host
- what can still be validated on a no-GPU build machine

The custom product is built under:

```bash
/home/azureuser/aosp/src/out/target/product/vsoc_arm64_only
```

The prepared plain-QEMU bundle is staged under:

```bash
/home/azureuser/aosp/plain-qemu
```

## Current Status

The image no longer depends on the cuttlefish harness to get through the real
boot-chain problems that were present earlier:

- duplicate Gatekeeper APEX fixed
- duplicate KeyMint APEX fixed
- duplicate graphics composer APEX fixed
- direct plain-QEMU boot reaches Android userspace without `run_cvd`

The remaining display-stack failures seen on this build machine are not strong
evidence of a bad image, because this machine does not provide a usable GPU
backend for the guest runtime that this product expects.

## Build Machine Limit

This machine is good for:

- compiling the image
- unpacking and staging the raw artifacts
- limited headless validation of kernel, init, dynamic partitions, apexd,
  zygote, and `adbd`

This machine is not good for:

- final validation of the graphics stack
- final validation of SurfaceFlinger
- final validation of the cuttlefish display/light path

In practice, the no-GPU build machine can still validate that:

- the image boots without cuttlefish orchestration
- the GPT disk layout is correct
- first-stage init mounts the dynamic partitions correctly
- vendor APEX activation succeeds
- `adbd` starts

It cannot fully validate a graphics-dependent Android boot for this product.

## Step 1: Prepare The Bundle On The Build Machine

Run:

```bash
cd /home/azureuser/aosp
./scripts/prepare_plain_qemu.sh
```

This produces:

- `/home/azureuser/aosp/plain-qemu/kernel`
- `/home/azureuser/aosp/plain-qemu/initrd.img`
- `/home/azureuser/aosp/plain-qemu/os-disk.raw`
- `/home/azureuser/aosp/plain-qemu/kernel.cmdline`
- `/home/azureuser/aosp/plain-qemu/super.raw`
- `/home/azureuser/aosp/plain-qemu/userdata.raw`

What the script does:

- unpacks `boot.img` and `vendor_boot.img`
- extracts the kernel, vendor ramdisk, dtb, and bootconfig
- converts `super.img` and `userdata.img` from sparse to raw
- creates `misc.img` and `metadata.img`
- builds a single GPT disk image `os-disk.raw`
- appends bootconfig to the vendor ramdisk to form `initrd.img`

## Step 2: Copy The Prepared Bundle To The Runtime Host

Copy the whole staging directory:

```bash
rsync -av /home/azureuser/aosp/plain-qemu/ user@runtime-host:/path/plain-qemu/
```

Only the prepared bundle is required on the runtime host. The full AOSP tree is
not required there.

## Step 3: Runtime Host Requirements

The runtime host should have:

- `qemu-system-aarch64`
- a working OpenGL/EGL-capable GPU stack
- QEMU support for at least:
  - `virtio-gpu-gl-pci`
  - `egl-headless` or `gtk`

Useful checks:

```bash
qemu-system-aarch64 -device help | grep virtio-gpu
qemu-system-aarch64 -display help
```

Expected useful output includes:

- `virtio-gpu-gl-pci`
- `egl-headless`

## Step 4: Launch On The GPU-Capable Runtime Host

The launcher script supports both a headless builder validation mode and a
GPU-backed runtime mode.

GPU-backed runtime mode:

```bash
cd /path
export STAGE=/path/plain-qemu
export QEMU_DISPLAY=egl-headless
export QEMU_GPU_DEVICE='virtio-gpu-gl-pci,id=gpu0,xres=720,yres=1280'
export QEMU_HOST_ADB_PORT=6520
/home/azureuser/aosp/scripts/run_plain_qemu.sh
```

If the runtime host has a desktop session and working GL windowing, this is
also reasonable:

```bash
export QEMU_DISPLAY='gtk,gl=on'
export QEMU_GPU_DEVICE='virtio-gpu-gl-pci,id=gpu0,xres=720,yres=1280'
```

Important detail:

- the guest still boots from the same `kernel`, `initrd.img`, and `os-disk.raw`
- only the host-side QEMU display and GPU device selection changes

## Step 5: Headless Validation On The Build Machine

Yes, partial validation is possible without host graphics.

Use:

```bash
cd /home/azureuser/aosp
export QEMU_DISPLAY=none
export QEMU_GPU_DEVICE='virtio-gpu-pci,id=gpu0,xres=720,yres=1280'
export QEMU_HOST_ADB_PORT=6520
timeout 120s ./scripts/run_plain_qemu.sh
```

This is useful to validate:

- kernel boot
- init and early userspace
- dynamic-partition activation
- vendor APEX mounting
- `zygote`
- `adbd`

This is not a full product validation because SurfaceFlinger and related
graphics services still depend on a real runtime host graphics backend.

Use a non-emulator host ADB port such as `6520`. Forwarding guest `5555` to
host `5555` collides with ADB's built-in emulator port scan and can produce a
misleading offline `emulator-5554` transport on the host.

## Step 5A: Software-Rendered Host Graphics On A No-GPU Server

If the server has no physical GPU, QEMU can still be given a software OpenGL
host path with Xvfb plus Mesa llvmpipe.

Install:

```bash
sudo apt-get update
sudo apt-get install -y xvfb mesa-utils mesa-utils-bin
```

Sanity-check the host renderer:

```bash
xvfb-run -s '-screen 0 1280x1024x24' \
  bash -lc 'LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe glxinfo -B'
```

Expected renderer:

- `OpenGL renderer string: llvmpipe`

Launch QEMU with software-rendered host GL:

```bash
cd /home/azureuser/aosp
xvfb-run -s '-screen 0 1280x1024x24' \
  bash -lc "LIBGL_ALWAYS_SOFTWARE=1 \
    GALLIUM_DRIVER=llvmpipe \
    QEMU_DISPLAY='gtk,gl=on' \
    QEMU_GPU_DEVICE='virtio-gpu-gl-pci,id=gpu0,xres=720,yres=1280' \
    QEMU_HOST_ADB_PORT=6520 \
    ./scripts/run_plain_qemu.sh"
```

Important limitation:

- this host does not have `/dev/dri/renderD*`, so `QEMU_DISPLAY=egl-headless`
  cannot be used here
- `gtk,gl=on` under `Xvfb` does work with llvmpipe on this machine
- however, with the current image, `surfaceflinger` still crashes repeatedly
  even with host-side software GL

So host-side software rendering is possible, but it does not by itself solve
the current guest image issue.

## What Headless Validation Already Proved

On the build machine, direct plain-QEMU boot already proved that:

- the image boots without the cuttlefish harness
- the duplicate vendor APEX packaging issues are resolved
- the guest reaches Android userspace
- `adbd` starts

The later SurfaceFlinger failures on the builder should be treated as a runtime
host limitation unless they can also be reproduced on a GPU-capable target host.

## Current Builder-Side Caveats

The builder-side serial log still shows some expected limitations:

- `surfaceflinger` aborts later in boot
- `vendor.light-cuttlefish` aborts
- `vendor.threadnetwork_hal` aborts

Those are not sufficient on their own to justify changing the built image
again, because they are being observed on a host that is not suitable for final
graphics validation.

## If A Full No-GPU Validation Target Is Required

If you want a product that can fully boot to a meaningful validated state on a
host with no GPU backend at all, that is a different deliverable.

That would require a separate headless flavor that deliberately removes or
disables some graphics-dependent services, likely including:

- graphics composer
- light HAL pieces tied to cuttlefish display plumbing
- possibly additional display-related vendor configuration

That work would be source changes plus a rebuild. It is not the same thing as
validating the current GPU-intended artifact.

## Files Involved

- build output: `/home/azureuser/aosp/src/out/target/product/vsoc_arm64_only`
- prep script: `/home/azureuser/aosp/scripts/prepare_plain_qemu.sh`
- launch script: `/home/azureuser/aosp/scripts/run_plain_qemu.sh`
- staged bundle: `/home/azureuser/aosp/plain-qemu`
