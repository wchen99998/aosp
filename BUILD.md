# AOSP QEMU Build Notes

## Workspace

- Root: `/home/azureuser/aosp`
- Source tree: `/home/azureuser/aosp/src`

## Sync Status

The repo sync completed successfully. The source checkout is present under `src/`.

## Host Prerequisite

This tree requires `rsync` during the build. On this machine it was missing and caused the build to fail during AIDL code generation with `/bin/sh: 1: rsync: not found`.

Install it with:

```bash
sudo apt-get update
sudo apt-get install -y rsync
```

## QEMU Product

The custom lunch target is:

```bash
aosp_cf_arm64_only_phone_qemu-trunk_staging-userdebug
```

It resolves to:

- `TARGET_PRODUCT=aosp_cf_arm64_only_phone_qemu`
- `TARGET_ARCH=arm64`

## Build Commands

Run from `/home/azureuser/aosp/src`:

```bash
source build/envsetup.sh
lunch aosp_cf_arm64_only_phone_qemu-trunk_staging-userdebug
m -j$(nproc)
```

## Current QEMU-Specific Changes

The build currently uses the stock cuttlefish vendor init file plus an additional QEMU-specific init fragment, instead of replacing `init.cutf_cvm.rc`.

Why:

- Replacing the stock init module caused an install-path conflict because both prebuilts tried to install `vendor/etc/init/init.cutf_cvm.rc`.
- The current graph-valid approach is to keep the stock module and install a separate QEMU fragment as `vendor/etc/init/init.qemu.rc`.

The QEMU product currently adds:

- `persist.adb.tcp.port=5555`
- `ro.vendor.disable_rename_eth0=1`
- `ro.cuttlefish.guest_profile=cuttlefish-qemu`
- `ro.cuttlefish.adb_transport=rawTcp`
- `ro.cuttlefish.guest_adb_port=5555`
- `ro.hardware.egl=mesa`
- `device_google_cuttlefish_qemu_config_init_vendor_rc`

The QEMU init fragment currently:

- stops `setup_wifi`
- stops `init_wifi_sh`
- brings up `eth0`
- stops `socket_vsock_proxy`

## Important Caveat

The original attempt to strip inherited `PRODUCT_PACKAGES`, `PRODUCT_HOST_PACKAGES`, and `PRODUCT_VENDOR_PROPERTIES` from the child product makefile using `$(filter-out ...)` does not reliably subtract inherited values in this AOSP product inheritance model.

That means:

- the current target is buildable again
- the current target is not yet a fully stripped runtime-only QEMU flavor

If deeper runtime pruning is needed later, it should be done through supported upstream/product composition changes rather than child-level `filter-out` on inherited product lists.

## Current Build Status

After fixing the init-module conflict and installing `rsync`, the build restarted successfully and progressed past the previous failures.

To continue the incremental build:

```bash
cd /home/azureuser/aosp/src
source build/envsetup.sh
lunch aosp_cf_arm64_only_phone_qemu-trunk_staging-userdebug
m -j$(nproc)
```
